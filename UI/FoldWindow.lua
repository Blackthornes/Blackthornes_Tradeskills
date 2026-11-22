-- UI/FoldWindow.lua
-- The fold gem: a small gold gem beside a window's close gem. A click folds
-- the window into a round button, the addon's badge in a gold ring, on the
-- window's top right corner (a player asked for a minimize button, the owner
-- picked the mockup, 2026-10-24; the round button, 2026-11-22). A click on
-- the button opens the window again, the same size, wherever the button is.
--
-- The button can be dragged, never leaves the screen and keeps its spot in
-- windowSpots["fold:" .. key]. A window stays a button through /reload and
-- logging out (foldedWindows[key]; never rename either) until the button is
-- clicked. Closing the window, by its close gem, a command or the minimap
-- button, opens it full next time.
--
-- Folded, the window is still shown but empty: everything on it hides, and
-- it takes no clicks, so the window's own code goes on as before. Escape
-- leaves it alone.
--
-- Panels that stay up while you play join with FoldWindow:Join (their own
-- fold gem, from HouseKit), windows with a house frame with FoldWindow:Add.
-- With the Blizzard window style the gem is the game's own minimize art when
-- the client has it.
--
-- The same file in all five Blackthornes addons (a fix to it belongs in all
-- five), as is tools/make_fold_art.py, which draws Media/Frame/FoldGem.tga.

local ADDON, ns = ...

local FoldWindow = {}
ns.FoldWindow = FoldWindow

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local MEDIA = ([[Interface\AddOns\%s\Media\Frame\]]):format(ADDON)
FoldWindow.MEDIA = MEDIA

-- The round button, how far it sits out past the window's top right corner
-- (where the fold gem is),
-- and how far a newer one steps down off an older one it would cover.
FoldWindow.SIZE = 46
FoldWindow.OUT = 8
FoldWindow.STEP = 6
-- The badge inside the ring, as the house portrait has it (36 in 68).
local EMBLEM = 0.53

-- Seconds after logging in before windows that were folded come back as
-- buttons, so windows the addons open at login are up first.
FoldWindow.RESTORE_AFTER = 2

-- The gem, and how far it sits left of the close gem's middle.
local GEM = 22
local GAP = 2

-- The dark bar on the gem, the gold of its glow and of the button's name.
local INK = { 0.165, 0.110, 0.024 }
local GOLD = { 0.910, 0.784, 0.451 }
local NAME = { 1, 0.82, 0 }
local PILL_BACK = { 0.059, 0.047, 0.031 }
local PILL_EDGE = { 0.722, 0.580, 0.247 }

-- The game's own minimize art, for the Blizzard window style.
local ATLAS = {
    fold = { "RedButton-Condense", "RedButton-Condense-Pressed" },
    highlight = "RedButton-Highlight",
}

-- Buttons of every Blackthornes addon, so a newer one never lands on top of
-- an older one.
local hub = _G.BlackthornesFoldHub
if type(hub) ~= "table" then
    hub = { rounds = {} }
    _G.BlackthornesFoldHub = hub
end
hub.rounds = hub.rounds or {}

-- This copy's windows and buttons, by key.
FoldWindow.states = {}
FoldWindow.hosts = {}
FoldWindow.rounds = {}
-- Keys already brought back (or not) since logging in.
FoldWindow.restored = {}
-- Where the saves are kept when no addon save is there (tests).
FoldWindow.memory = {}

-- Our own fields, read raw: some test frames answer any missing field with
-- a function.
local function Field(object, key)
    if type(object) ~= "table" then return nil end
    return rawget(object, key)
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, object, ...)
end

local function Number(object, method)
    local ok, value = Call(object, method)
    if ok and type(value) == "number" then return value end
    return nil
end

local function Scale(object)
    local value = Number(object, "GetEffectiveScale")
    if value and value > 0 then return value end
    return 1
end

local function Protected(frame)
    local ok, protected = Call(frame, "IsProtected")
    return ok and protected == true
end

local function Shown(object)
    local ok, shown = Call(object, "IsShown")
    return ok and shown == true
end

local function Later(fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0, fn)
    else
        fn()
    end
end

--------------------------------------------------------------------------------
-- The saves
--------------------------------------------------------------------------------

local function ReadSave(name)
    local shared = ns.SharedWindow
    if type(shared) == "table" and type(shared.ReadSave) == "function" then
        local ok, value = pcall(shared.ReadSave, name)
        if ok and value ~= nil then return value end
    end
    return FoldWindow.memory[name]
end

local function WriteSave(name, value)
    local shared = ns.SharedWindow
    if type(shared) == "table" and type(shared.WriteSave) == "function" then
        -- No save loaded yet: kept for the session.
        local ok, count = pcall(shared.WriteSave, name, value)
        if ok and type(count) == "number" and count > 0 then
            FoldWindow.memory[name] = nil
            return
        end
    end
    FoldWindow.memory[name] = value
end

-- A copy of a saved table with one key changed, so every save gets the same.
local function Put(name, key, value)
    local copy, old = {}, ReadSave(name)
    if type(old) == "table" then for k, v in pairs(old) do copy[k] = v end end
    copy[key] = value
    WriteSave(name, next(copy) ~= nil and copy or nil)
end

--- Is this window kept as a button?
function FoldWindow.SavedFolded(key)
    local saved = ReadSave("foldedWindows")
    return type(saved) == "table" and saved[key] == true
end

-- Windows with no name and no key: folded for the session only.
FoldWindow.unsaved = {}

local function SaveFolded(key, on)
    if not key or FoldWindow.unsaved[key] or FoldWindow.SavedFolded(key) == (on and true or false) then return end
    Put("foldedWindows", key, on and true or nil)
end

local function SavedSpot(key)
    local spots = ReadSave("windowSpots")
    local spot = type(spots) == "table" and spots["fold:" .. key]
    if type(spot) == "table" and type(spot.x) == "number" and type(spot.y) == "number" then
        return spot
    end
    return nil
end

local function SaveSpot(key, x, y)
    if not key or FoldWindow.unsaved[key] or type(x) ~= "number" or type(y) ~= "number" then return end
    Put("windowSpots", "fold:" .. key, { x = x, y = y })
end

--------------------------------------------------------------------------------
-- The round button
--------------------------------------------------------------------------------

-- The button's top left, in screen pixels.
local function RoundSpot(round)
    local button = round.button
    local left, top = Number(button, "GetLeft"), Number(button, "GetTop")
    if not (left and top) then return nil end
    local scale = Scale(button)
    return left * scale, top * scale
end

local function PutRound(round, x, y)
    local button = round.button
    local scale = Scale(button)
    Call(button, "ClearAllPoints")
    Call(button, "SetPoint", "TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    round.x, round.y = x, y
end

--- Step a button down off any other one it would cover, older ones first.
function FoldWindow.Unstack(x, y, others, size)
    size = size or FoldWindow.SIZE
    for _ = 1, 12 do
        local moved = false
        for _, other in ipairs(others) do
            if math.abs(other[1] - x) < size and math.abs(other[2] - y) < size then
                y = other[2] - size - FoldWindow.STEP
                moved = true
            end
        end
        if not moved then break end
    end
    return x, y
end

local function OthersShown(round)
    local list = {}
    for _, other in ipairs(hub.rounds) do
        if other ~= round and Shown(other.button) then
            local x, y = RoundSpot(other)
            if x and y then list[#list + 1] = { x, y } end
        end
    end
    return list
end

local function Host(key)
    return FoldWindow.hosts[key] or {}
end

local function Text(value)
    if type(value) == "function" then
        local ok, text = pcall(value)
        if ok and type(text) == "string" then return text end
        return nil
    end
    if type(value) == "string" then return value end
    return nil
end

local function Title(key)
    local host = Host(key)
    local title = Text(host.title)
    if title then return title end
    local state = FoldWindow.states[key]
    local plate = state and Field(Field(state.frame, "titan"), "plate")
    local label = Field(plate, "label")
    if label then
        local ok, words = Call(label, "GetText")
        if ok and type(words) == "string" and words ~= "" then return words end
    end
    return nil
end

local function Tooltip(round)
    if not GameTooltip then return end
    GameTooltip:SetOwner(round.button, "ANCHOR_RIGHT")
    local title = Title(round.key)
    if title then
        GameTooltip:SetText(title, NAME[1], NAME[2], NAME[3])
    end
    local line = Text(Host(round.key).line)
    if line then GameTooltip:AddLine(line, 1, 1, 1, true) end
    if title then
        GameTooltip:AddLine(L["Click to open it again."], 1, 1, 1)
    else
        GameTooltip:SetText(L["Click to open it again."], 1, 1, 1)
    end
    GameTooltip:AddLine(L["Drag to move it."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

--- The small number under a button: kills, goals. Hidden when there is none.
function FoldWindow.Pill(round)
    local pill = round and round.pill
    if not pill then return end
    local text = Text(Host(round.key).pill)
    if text and text ~= "" then
        if round.pillText ~= text then
            round.pillText = text
            Call(pill.label, "SetText", text)
            local width = Number(pill.label, "GetStringWidth") or (#text * 6)
            Call(pill, "SetWidth", math.max(18, math.ceil(width) + 12))
        end
        Call(pill, "Show")
    else
        round.pillText = nil
        Call(pill, "Hide")
    end
end

local function Light(round, p)
    if round.halo then Call(round.halo, "SetAlpha", 0.3 + 0.5 * p) end
    if round.lit then Call(round.lit, "SetAlpha", 0.45 * p) end
end

local function MakePill(button)
    local pill = CreateFrame("Frame", nil, button)
    pill:SetSize(24, 15)
    pill:SetPoint("CENTER", button, "BOTTOM", 0, 1)
    local edge = pill:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(pill)
    edge:SetColorTexture(PILL_EDGE[1], PILL_EDGE[2], PILL_EDGE[3], 1)
    local back = pill:CreateTexture(nil, "BORDER")
    back:SetPoint("TOPLEFT", 1, -1)
    back:SetPoint("BOTTOMRIGHT", -1, 1)
    back:SetColorTexture(PILL_BACK[1], PILL_BACK[2], PILL_BACK[3], 1)
    if type(pill.CreateFontString) == "function" then
        local label = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if label then
            pcall(label.SetPoint, label, "CENTER", 0, 0)
            pcall(label.SetTextColor, label, 1, 1, 1)
            pill.label = label
        end
    end
    pill:Hide()
    return pill
end

local Open

--- The button for `key`, made the first time it is asked for.
function FoldWindow.Round(key)
    local round = FoldWindow.rounds[key]
    if round then return round end
    if type(CreateFrame) ~= "function" then return nil end

    local button = CreateFrame("Button", nil, UIParent)
    round = { key = key, button = button }
    FoldWindow.rounds[key] = round
    hub.rounds[#hub.rounds + 1] = round

    local size = FoldWindow.SIZE
    button:SetSize(size, size)
    Call(button, "SetFrameStrata", "HIGH")
    Call(button, "SetClampedToScreen", true)
    Call(button, "SetMovable", true)
    Call(button, "EnableMouse", true)
    Call(button, "RegisterForDrag", "LeftButton")
    Call(button, "RegisterForClicks", "LeftButtonUp")

    local host = Host(key)
    local halo = button:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture(MEDIA .. "Glow")
    halo:SetPoint("CENTER")
    halo:SetSize(size * 1.6, size * 1.6)
    halo:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    pcall(halo.SetBlendMode, halo, "ADD")
    round.halo = halo

    local ring = button:CreateTexture(nil, "ARTWORK")
    ring:SetTexture(MEDIA .. "Portrait")
    ring:SetAllPoints(button)

    local emblem = button:CreateTexture(nil, "ARTWORK", nil, 2)
    emblem:SetTexture(host.emblem or (MEDIA .. "Emblem"))
    emblem:SetSize(math.floor(size * EMBLEM + 0.5), math.floor(size * EMBLEM + 0.5))
    emblem:SetPoint("CENTER", 0, 1)
    round.emblem = emblem

    local lit = button:CreateTexture(nil, "OVERLAY")
    lit:SetTexture(MEDIA .. "Portrait")
    lit:SetAllPoints(button)
    pcall(lit.SetBlendMode, lit, "ADD")
    round.lit = lit
    Light(round, 0)

    round.pill = MakePill(button)

    local function Blend(p)
        if ns.Motion and type(ns.Motion.Blend) == "function" then
            ns.Motion:Blend(button, "hover", p, p > 0 and 0.12 or 0.18, function(v) Light(round, v) end)
        else
            Light(round, p)
        end
    end

    button:SetScript("OnEnter", function()
        round.hovered = true
        Blend(1)
        FoldWindow.Pill(round)
        Tooltip(round)
    end)
    button:SetScript("OnLeave", function()
        round.hovered = false
        Blend(0)
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnDragStart", function(self)
        round.dragging = true
        Call(self, "StartMoving")
    end)
    button:SetScript("OnDragStop", function(self)
        Call(self, "StopMovingOrSizing")
        round.dragging = false
        round.dropped = true
        local x, y = RoundSpot(round)
        if x and y then
            -- Pinned by its top left again, wherever the game left it.
            PutRound(round, x, y)
            SaveSpot(key, x, y)
            round.moved = true
        end
    end)
    button:SetScript("OnClick", function()
        -- Let go after a drag: that was a move, not a click.
        if round.dropped then round.dropped = false return end
        Open(round)
    end)
    button:Hide()
    return round
end

local function ShowRound(round, x, y, unstack)
    if unstack then x, y = FoldWindow.Unstack(x, y, OthersShown(round)) end
    PutRound(round, x, y)
    round.moved, round.dropped = false, false
    FoldWindow.Pill(round)
    Call(round.button, "Show")
    SaveSpot(round.key, x, y)
end

local function HideRound(round)
    if not round then return end
    round.ghost = false
    Call(round.button, "Hide")
    if round.hovered and GameTooltip then GameTooltip:Hide() end
    round.hovered = false
end

--- Update a folded window's button: its number, and its tooltip if the
--- mouse is on it. For the window's own code, when its count changes.
function FoldWindow:Refresh(frameOrKey)
    local key = frameOrKey
    if type(frameOrKey) == "table" then
        local state = Field(frameOrKey, "blackthornesFold")
        key = state and state.key
    end
    local round = key and FoldWindow.rounds[key]
    if not round or not Shown(round.button) then return end
    FoldWindow.Pill(round)
    if round.hovered then Tooltip(round) end
end

--------------------------------------------------------------------------------
-- Folding
--------------------------------------------------------------------------------

local function State(frame)
    return Field(frame, "blackthornesFold")
end

--- Is this window folded into its button?
function FoldWindow:IsFolded(frame)
    local state = State(frame)
    return state ~= nil and state.folded == true
end

-- Hide a piece while folded, and keep it hidden if the window shows it
-- again; remember it, so opening the window brings it back. A piece the
-- window hides itself while folded stays hidden.
local function Watch(state, piece, isFrame)
    if state.watched[piece] then return end
    state.watched[piece] = true

    local function Again(self)
        if state.folded and not state.busy and (not isFrame or Call(self, "GetParent") and self:GetParent() == state.frame) then
            if isFrame and Protected(self) and InCombat() then return end
            state.hidden[self] = isFrame and "frame" or "region"
            state.busy = true
            Call(self, "Hide")
            state.busy = false
        end
    end
    local function Gone(self)
        if state.folded and not state.busy then state.hidden[self] = nil end
    end
    if isFrame and type(piece.HookScript) == "function" then
        pcall(piece.HookScript, piece, "OnShow", Again)
    elseif type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, piece, "Show", Again)
    end
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, piece, "Hide", Gone)
        pcall(hooksecurefunc, piece, "SetShown", function(self, on)
            if on then Again(self) else Gone(self) end
        end)
    end
end

local function HideFor(state, piece, isFrame)
    Watch(state, piece, isFrame)
    if not Shown(piece) then return end
    state.hidden[piece] = isFrame and "frame" or "region"
    state.busy = true
    Call(piece, "Hide")
    state.busy = false
end

-- Escape closes the game's open windows by name; a folded one is left out.
local function Special(frame, keep)
    local ok, name = Call(frame, "GetName")
    if not (ok and type(name) == "string") or type(UISpecialFrames) ~= "table" then return nil end
    if keep then
        for index = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[index] == name then
                table.remove(UISpecialFrames, index)
                return name
            end
        end
        return nil
    end
    return name
end

--- Fold the window into its button. False when it cannot be now: a button
--- the game guards is showing and a fight is on.
--
-- opts.restore: brought back after a /reload, so the button goes where it
-- was left rather than on the window's corner.
function FoldWindow:Fold(frame, opts)
    local state = State(frame)
    if not state or state.folded or not Shown(frame) then return false end
    if state.canFold and not state.canFold() then return false end

    -- Still rising into place as it opened: land it first, so the button
    -- goes where it settles.
    local motion = ns.Motion
    if motion and type(motion.Stop) == "function" then pcall(motion.Stop, motion, frame, "open", true) end

    local children = { Call(frame, "GetChildren") }
    table.remove(children, 1)
    if InCombat() then
        if Protected(frame) then return false end
        for _, child in ipairs(children) do
            if Shown(child) and Protected(child) then return false end
        end
    end

    local right, top = Number(frame, "GetRight"), Number(frame, "GetTop")
    if not (right and top) then
        -- A frame that can't say its right edge: its left and width.
        local left = Number(frame, "GetLeft")
        right = left and left + (Number(frame, "GetWidth") or 0)
    end
    if not (right and top) then return false end
    local round = state.key and FoldWindow.Round(state.key)
    if not round then return false end

    state.hidden = {}
    local regions = { Call(frame, "GetRegions") }
    table.remove(regions, 1)
    for _, region in ipairs(regions) do HideFor(state, region, false) end
    state.folding = true
    for _, child in ipairs(children) do HideFor(state, child, true) end
    state.folding = false

    local okMouse, mouse = Call(frame, "IsMouseEnabled")
    local okWheel, wheel = Call(frame, "IsMouseWheelEnabled")
    state.mouse = not okMouse or mouse ~= false
    state.wheel = okWheel and wheel == true
    Call(frame, "EnableMouse", false)
    Call(frame, "EnableMouseWheel", false)
    state.special = Special(frame, true)

    state.folded = true
    -- Hiding what is on it closed the window itself (a page inside the
    -- one window heard it hide and closed the one window, so it never came
    -- back from its button, 2026-11-22): it was a close, so open it full.
    if not Shown(frame) then
        FoldWindow:Unfold(frame, true)
        return false
    end
    if GameTooltip and Field(state.button, "hovered") then GameTooltip:Hide() end

    local spot = opts and opts.restore and SavedSpot(state.key)
    if spot then
        ShowRound(round, spot.x, spot.y, true)
    else
        -- On the window's top right corner, where the fold gem is.
        local scale, size = Scale(frame), Scale(round.button)
        ShowRound(round, right * scale + (FoldWindow.OUT - FoldWindow.SIZE) * size,
            top * scale + FoldWindow.OUT * size, true)
    end
    round.ghost = false
    SaveFolded(state.key, true)

    if state.onToggle then pcall(state.onToggle, true) end
    return true
end

-- Tell the window it was dropped where it now is, so it keeps that spot as
-- it would after a drag.
local function Dropped(frame)
    Call(frame, "StopMovingOrSizing")
    local ok, drop = Call(frame, "GetScript", "OnDragStop")
    if ok and type(drop) == "function" then pcall(drop, frame) end
end

-- Put the window's top right corner where the button says. Pinned by its
-- top left, as the windows' own drags leave them.
local function ToRound(frame, round)
    local x, y = RoundSpot(round)
    if not (x and y) then return false end
    if InCombat() and Protected(frame) then return false end
    local width = Number(frame, "GetWidth") or 0
    local scale, size = Scale(frame), Scale(round.button)
    Call(frame, "ClearAllPoints")
    Call(frame, "SetPoint", "TOPLEFT", UIParent, "BOTTOMLEFT",
        (x + (FoldWindow.SIZE - FoldWindow.OUT) * size) / scale - width, (y - FoldWindow.OUT * size) / scale)
    return true
end

--- Open a folded window again, where its button is. `closing` is true when
--- the window is being closed: it opens full next time.
function FoldWindow:Unfold(frame, closing)
    local state = State(frame)
    if not state or not state.folded then return false end
    local round = state.key and FoldWindow.rounds[state.key]

    state.busy = true
    if not closing and round and round.moved and ToRound(frame, round) then
        state.busy = false
        Dropped(frame)
        state.busy = true
    end
    if state.mouse ~= false then Call(frame, "EnableMouse", true) end
    if state.wheel then Call(frame, "EnableMouseWheel", true) end
    if state.special and type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, state.special)
    end
    state.special = nil
    state.folded = false

    for piece, kind in pairs(state.hidden) do
        local isFrame = kind == "frame"
        local stillOurs = not isFrame or (Call(piece, "GetParent") and piece:GetParent() == frame)
        if stillOurs then
            if isFrame and Protected(piece) and InCombat() then
                FoldWindow.waiting[piece] = frame
            else
                Call(piece, "Show")
            end
        end
    end
    state.hidden = {}
    state.busy = false

    HideRound(round)
    SaveFolded(state.key, false)

    if state.onToggle then pcall(state.onToggle, false, closing and true or false) end
    -- Growing back out of the button.
    if not closing and ns.Motion and type(ns.Motion.Open) == "function" then
        pcall(ns.Motion.Open, ns.Motion, frame, 0)
    end
    return true
end

function FoldWindow:Toggle(frame)
    if self:IsFolded(frame) then return self:Unfold(frame) end
    return self:Fold(frame)
end

-- Buttons the game guards that a fight kept hidden come back once it ends.
FoldWindow.waiting = {}

-- A click on the button: open the window it stands for.
Open = function(round)
    local state = FoldWindow.states[round.key]
    if state and state.folded then
        FoldWindow:Unfold(state.frame)
        return
    end
    -- After a /reload: the window is not up yet. Its own way of opening
    -- brings it up, full, where the button is.
    HideRound(round)
    SaveFolded(round.key, false)
    local host = Host(round.key)
    if type(host.open) == "function" then pcall(host.open) end
    state = FoldWindow.states[round.key]
    if state and Shown(state.frame) and not state.folded and ToRound(state.frame, round) then
        Dropped(state.frame)
    end
end

--------------------------------------------------------------------------------
-- Back after a /reload
--------------------------------------------------------------------------------

local function Owned(key)
    if FoldWindow.states[key] then return true end
    local host = FoldWindow.hosts[key]
    if host then
        if type(host.mine) == "function" then
            local ok, mine = pcall(host.mine)
            return ok and mine == true
        end
        return true
    end
    return type(key) == "string" and key:sub(1, #ADDON + 1) == ADDON .. ":"
end

-- The window showed. The first time since logging in, one kept as a button
-- folds again; one opened while its button waited after a /reload opens
-- full, and the button goes.
local function Showing(state)
    local key = state.key
    if not key or state.folded then return end
    local round = FoldWindow.rounds[key]
    if round and round.ghost then
        HideRound(round)
        SaveFolded(key, false)
        FoldWindow.restored[key] = true
        return
    end
    if FoldWindow.restored[key] then return end
    FoldWindow.restored[key] = true
    if FoldWindow.SavedFolded(key) then
        Later(function()
            if not state.folded and Shown(state.frame) then
                FoldWindow:Fold(state.frame, { restore = true })
            end
        end)
    end
end

--- Bring back, as buttons, the windows kept folded that are not up: their
--- own way of opening is used when the button is clicked. Runs once, a
--- moment after logging in.
function FoldWindow.Restore()
    local saved = ReadSave("foldedWindows")
    if type(saved) ~= "table" then return end
    local keys = {}
    for key in pairs(saved) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        if not FoldWindow.restored[key] and Owned(key) then
            FoldWindow.restored[key] = true
            local state = FoldWindow.states[key]
            local host = FoldWindow.hosts[key]
            if state and Shown(state.frame) then
                if not state.folded then FoldWindow:Fold(state.frame, { restore = true }) end
            elseif host and type(host.open) == "function" then
                local round = FoldWindow.Round(key)
                local spot = SavedSpot(key)
                if round and spot then
                    ShowRound(round, spot.x, spot.y, true)
                    round.ghost = true
                elseif round == nil or not spot then
                    SaveFolded(key, false)
                end
            else
                -- Nothing can open it from a button: next time it shows full.
                SaveFolded(key, false)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Joining
--------------------------------------------------------------------------------

local function Merge(key, opts)
    local host = FoldWindow.hosts[key] or {}
    for _, name in ipairs({ "title", "emblem", "line", "pill", "open", "mine" }) do
        if opts[name] ~= nil then host[name] = opts[name] end
    end
    FoldWindow.hosts[key] = host
    return host
end

--- The full key for a window: the addon's name and the window's.
function FoldWindow.Key(key, shared)
    if type(key) ~= "string" or key == "" then return nil end
    if shared then return key end
    return ADDON .. ":" .. key
end

--- Say how to open a window that is not built or not up yet, so its button
--- can come back after a /reload. Call at load time.
--
-- opts: open (shows the window), title, emblem (a texture path), line and
-- pill (functions giving the tooltip's line and the small number), shared
-- (the key as given, for the one window), mine (a function: false when
-- another addon draws this window).
function FoldWindow:Opener(key, opts)
    opts = opts or {}
    key = FoldWindow.Key(key, opts.shared)
    if not key then return nil end
    Merge(key, opts)
    return key
end

--- Let a window fold into a round button, with no gem of its own (a panel
--- that draws its own fold gem calls FoldWindow:Fold from it).
--
-- opts: key (saves it through a /reload; else the frame's name), shared,
-- title, emblem, line, pill, open (as for Opener), onToggle (called with
-- true as it folds and false as it opens, so the window can stop or start
-- drawing its lists; opening, a second true says the window is closing),
-- canFold (a function; while it answers false nothing
-- folds).
function FoldWindow:Join(frame, opts)
    if type(frame) ~= "table" then return nil end
    local state = State(frame)
    if state then return state end
    opts = opts or {}

    local key = opts.key
    if not key then
        local ok, name = Call(frame, "GetName")
        if ok and type(name) == "string" then key = name end
    end
    key = FoldWindow.Key(key, opts.shared)
    if not key then
        key = FoldWindow.Key((tostring(frame):gsub("^table: ", "")), false)
        FoldWindow.unsaved[key] = true
    end

    state = {
        frame = frame, key = key, folded = false, hidden = {}, watched = {},
        onToggle = opts.onToggle, canFold = opts.canFold,
    }
    frame.blackthornesFold = state
    FoldWindow.states[key] = state
    Merge(key, opts)

    -- Closed while folded, it opens full next time. Only a close (a Hide
    -- call: the close gem, a command), never the whole interface going out
    -- of sight, and not lost if the window sets its own OnHide.
    if type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, frame, "Hide", function(self)
            if not state.busy then FoldWindow:Unfold(self, true) end
        end)
    end
    if type(frame.HookScript) == "function" then
        pcall(frame.HookScript, frame, "OnShow", function() Showing(state) end)
    end
    if Shown(frame) then Showing(state) end
    return state
end

--------------------------------------------------------------------------------
-- The gem
--------------------------------------------------------------------------------

local function HasAtlas(name)
    local textures = C_Texture
    if type(textures) ~= "table" or type(textures.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(textures.GetAtlasInfo, name)
    return ok and info ~= nil
end

--- The gold gem with its glow, a lit copy for the mouse, and a bar drawn
--- from plain colour on its face.
local function Gem(button)
    local glow = button:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(MEDIA .. "Glow")
    glow:SetPoint("CENTER")
    glow:SetSize(GEM * 2.2, GEM * 2.2)
    glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    pcall(glow.SetBlendMode, glow, "ADD")

    local gem = button:CreateTexture(nil, "ARTWORK")
    gem:SetTexture(MEDIA .. "FoldGem")
    gem:SetAllPoints(button)

    local lit = button:CreateTexture(nil, "ARTWORK", nil, 1)
    lit:SetTexture(MEDIA .. "FoldGem")
    lit:SetAllPoints(button)
    pcall(lit.SetBlendMode, lit, "ADD")

    local across = button:CreateTexture(nil, "OVERLAY", nil, 2)
    across:SetColorTexture(INK[1], INK[2], INK[3], 1)
    across:SetSize(10, 3)
    across:SetPoint("CENTER", 0, 0)

    local function Light(p)
        glow:SetAlpha(0.25 + 0.55 * p)
        lit:SetAlpha(0.45 * p)
    end
    Light(0)

    button.Light = Light
    button.glyph = { across = across }
end

local function Atlas(button)
    for _, name in ipairs({ ATLAS.fold[1], ATLAS.fold[2], ATLAS.highlight }) do
        if not HasAtlas(name) then return false end
    end
    if not (Call(button, "SetNormalAtlas", ATLAS.fold[1])
        and Call(button, "SetPushedAtlas", ATLAS.fold[2])
        and Call(button, "SetHighlightAtlas", ATLAS.highlight, "ADD")) then
        return false
    end
    button.atlas = true
    return true
end

function FoldWindow.Tooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(L["Collapse this window"], 1, 1, 1)
    GameTooltip:Show()
end

--- Give a dressed window (Titanforged:Dress, or the Blizzard style's) its
--- fold gem, left of its close gem. Takes the same opts as FoldWindow:Join.
--- Returns the gem.
function FoldWindow:Add(frame, opts)
    local trim = Field(frame, "titan")
    if not trim then return nil end
    local old = State(frame)
    if old and old.button then return old.button end
    local state = FoldWindow:Join(frame, opts)
    if not state then return nil end

    local button = CreateFrame("Button", nil, trim)
    state.button = button

    local close = Field(trim, "closeButton")
    local size = GEM
    if Field(trim, "blizzard") then
        local closeSize = close and Number(close, "GetWidth")
        if closeSize and closeSize > 0 then size = closeSize end
    end
    button:SetSize(size, size)
    if close then
        local closeSize = Number(close, "GetWidth") or 26
        button:SetPoint("CENTER", close, "CENTER", -(closeSize / 2 + size / 2 + GAP), 0)
    else
        button:SetPoint("CENTER", trim, "TOPRIGHT", -8, -8)
    end

    if not (Field(trim, "blizzard") and Atlas(button)) then Gem(button) end

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        if Field(self, "Light") then
            if ns.Motion and type(ns.Motion.Blend) == "function" then ns.Motion:Blend(self, "hover", 1, 0.12, self.Light) else self.Light(1) end
        end
        FoldWindow.Tooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        if Field(self, "Light") then
            if ns.Motion and type(ns.Motion.Blend) == "function" then ns.Motion:Blend(self, "hover", 0, 0.18, self.Light) else self.Light(0) end
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function() FoldWindow:Toggle(frame) end)
    return button
end

-- One listener: the end of a fight, for guarded buttons it held back, and
-- logging in, to bring back windows kept as buttons.
if type(CreateFrame) == "function" then
    local ok, listener = pcall(CreateFrame, "Frame")
    if ok and listener and listener.RegisterEvent then
        pcall(listener.RegisterEvent, listener, "PLAYER_REGEN_ENABLED")
        pcall(listener.RegisterEvent, listener, "PLAYER_LOGIN")
        listener:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGIN" then
                if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                    C_Timer.After(FoldWindow.RESTORE_AFTER, FoldWindow.Restore)
                else
                    FoldWindow.Restore()
                end
                return
            end
            for piece, frame in pairs(FoldWindow.waiting) do
                FoldWindow.waiting[piece] = nil
                if not FoldWindow:IsFolded(frame) and Call(piece, "GetParent") and piece:GetParent() == frame then
                    Call(piece, "Show")
                end
            end
        end)
    end
end
