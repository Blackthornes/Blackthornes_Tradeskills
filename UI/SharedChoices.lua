-- Blackthornes -- UI/SharedChoices.lua
-- Choices set once for every addon (the owner said build it, 2026-10-29,
-- from the unified look's mockups): Text Size, Window Style, Effects, Use
-- TomTom, Guide Me and Arrow Size. A change to one in any addon is written
-- to every Blackthornes addon loaded, as the sister note's "Sister Addons"
-- has done since 2026-10-11. Nothing moves until the player changes one, and
-- every addon keeps its own saved key under its own name.
--
-- There is no shared core addon: every copy signs up in
-- `_G.BlackthornesSharedChoices`. Each addon joins with how it writes a
-- choice its own way (its own setter, so a live change shows at once), and
-- calls :Changed after the player changes one there. A change heard from a
-- sister is never sent on again. The same file in all five addons (a fix to
-- it belongs in all five).
--
--   ns.SharedChoices:Join(name, write)   write(choice, value)
--   ns.SharedChoices:Changed(choice, value)
--
-- Choices and values: textSize ("normal", "large", "larger"), windowStyle
-- ("titanforged", "blizzard"), effects ("full", "subtle", "off"),
-- useTomTom and arrowRoute (true or false), arrowSize (50, 75 or 100),
-- muteSounds (true or false).
--
-- Mute All Sounds (a player asked, the owner said build it, 2026-11-12):
-- one switch quiets every sound every Blackthornes addon plays. The state
-- lives on the shared board, so all addons go quiet the moment it is
-- ticked in any one. Each addon also keeps it in its own save as
-- `muteSounds` and `muteSoundsAt` (never rename them). Each addon joins
-- with how to read those two (readMute, nil until its save is loaded), and
-- the first sound asked for after a save loads takes what it kept, the
-- newest winning, so an addon that was turned off when the box was ticked
-- still goes quiet.
--
--   ns.SharedChoices:Join(name, write, readMute)   readMute() -> on, at
--   ns.SharedChoices:SetMute(on)        the player changed it here
--   ns.SharedChoices:Muted()            true while every sound is off
--   ns.Muted()                          the same, for the play calls
--
-- Look choices (Discord asks, the owner said build it, 2026-11-26): Font
-- (house, game or clear), Colors (warm or darker) and Fold Gem (round or
-- bar), for every addon at once. Each starts on what players had before,
-- so nothing changes until someone picks. They are kept in every loaded
-- addon's own save as `lookChoices = { font, colors, fold, at }` (never
-- rename it), the newest `at` winning, as One Window is. The font and
-- colors are read once, the first time an addon draws after its save is
-- in, so a change to them waits for /reload; the fold gem's pick counts
-- from the next fold.
--
-- Clear is Liberation Sans (SIL Open Font License 1.1, Media/Fonts with
-- its license beside it), which has Russian letters. It has no Chinese or
-- Korean ones, so on those clients Clear draws the house font.
--
--   ns.SharedChoices:Look(kind)          what the player picked
--   ns.SharedChoices:SetLook(kind, value)   the player picked it here
--   ns.SharedChoices:Drawn(kind)         font or colors, as drawn now
--   ns.SharedChoices:FontPath(house)     the font file to draw with
--   ns.SharedChoices:Recolor(colors)     Darker, put into a palette

local ADDON, ns = ...

local Shared = {}
ns.SharedChoices = Shared

Shared.CHOICES = {
    textSize = true, windowStyle = true, effects = true,
    useTomTom = true, arrowRoute = true, arrowSize = true,
    muteSounds = true, look = true,
}

local board = rawget(_G, "BlackthornesSharedChoices")
if type(board) ~= "table" then
    board = {}
    _G.BlackthornesSharedChoices = board
end
if type(board.members) ~= "table" then board.members = {} end
if type(board.mute) ~= "table" then board.mute = { on = false, at = 0 } end
if type(board.muteReaders) ~= "table" then board.muteReaders = {} end
if type(board.lookSaves) ~= "table" then board.lookSaves = {} end
Shared.board = board

--- At login: what this addon's save says. The newest answer among the
--- addons loaded wins.
function Shared:NoteMute(on, at)
    at = tonumber(at) or 0
    if at > (tonumber(board.mute.at) or 0) then
        board.mute.on = on == true
        board.mute.at = at
    end
end

--- The player ticked or unticked Mute All Sounds here: every addon hears
--- it at once, through the board, and is told so it saves it too. The
--- caller saves it in its own addon. Returns the time it was set.
function Shared:SetMute(on, at)
    board.mute.on = on == true
    board.mute.at = tonumber(at) or (type(time) == "function" and time()) or 0
    self:Changed("muteSounds", board.mute.on)
    return board.mute.at
end

--- Each save read once it has loaded: what it kept counts, newest first.
local function ReadSaves()
    for name, read in pairs(board.muteReaders) do
        local ok, on, at = pcall(read)
        if ok and on ~= nil then
            board.muteReaders[name] = nil
            Shared:NoteMute(on, at)
        elseif not ok then
            board.muteReaders[name] = nil
        end
    end
end

function Shared:Muted()
    if next(board.muteReaders) then ReadSaves() end
    return board.mute.on == true
end

--- For every play call: true while every Blackthornes sound is off.
function ns.Muted()
    return Shared:Muted()
end

--- This addon signs up, with how it writes a choice.
function Shared:Join(name, write, readMute)
    if type(name) ~= "string" or type(write) ~= "function" then return end
    self.name = name
    board.members[name] = write
    if type(readMute) == "function" then board.muteReaders[name] = readMute end
end

--- The player changed a choice in this addon: every other addon loaded
--- takes it too. Returns how many others took it.
function Shared:Changed(choice, value)
    if not self.CHOICES[choice] then return 0 end
    -- Heard from a sister: written here already, never sent on again.
    if board.busy then return 0 end
    board.busy = true
    local count = 0
    for name, write in pairs(board.members) do
        if name ~= self.name then
            local ok, err = pcall(write, choice, value)
            if ok then
                count = count + 1
            elseif ns.Debug then
                ns.Debug("shared choice:", tostring(err))
            end
        end
    end
    board.busy = false
    return count
end

--------------------------------------------------------------------------------
-- Look choices
--------------------------------------------------------------------------------

-- Each kind's values, the first the one players had before.
Shared.LOOKS = {
    font = { "house", "game", "clear" },
    colors = { "warm", "darker" },
    fold = { "round", "bar" },
}

Shared.CLEAR_FONT = ([[Interface\AddOns\%s\Media\Fonts\LiberationSans-Regular.ttf]]):format(ADDON or "")

-- Clients whose letters the clear font does not have.
Shared.NO_CLEAR = { zhCN = true, zhTW = true, koKR = true }

-- Darker (the mockup's cooler, deeper base): the same dark glass with the
-- warm tint taken out. The gold rim, buttons and edges stay.
Shared.DARKER = {
    window      = { 0.035, 0.035, 0.043 },   -- #09090B
    panel       = { 0.047, 0.047, 0.055 },   -- #0C0C0E
    header      = { 0.075, 0.075, 0.086 },   -- #131316
    row         = { 0.098, 0.098, 0.110 },   -- #19191C
    rowAlt      = { 0.075, 0.075, 0.086 },   -- #131316
    rowHover    = { 0.125, 0.125, 0.141 },   -- #202024
    glass       = { 0.063, 0.063, 0.075 },   -- #101013
    glassAlt    = { 0.031, 0.031, 0.039 },   -- #08080A, the well itself
    glassHover  = { 0.098, 0.098, 0.114 },   -- #19191D
    glassActive = { 0.122, 0.110, 0.071 },   -- #1F1C12, gold in the dark
    well        = { 0.031, 0.031, 0.039 },   -- #08080A
}

-- This addon's save, nil until it loads.
board.lookSaves[ADDON or "?"] = function()
    local db = rawget(ns, "db")
    if type(db) == "table" then return db end
    return nil
end

local function Valid(kind, value)
    for _, each in ipairs(Shared.LOOKS[kind] or {}) do
        if each == value then return true end
    end
    return false
end
Shared.ValidLook = Valid

local function EachSave(fn)
    for _, read in pairs(board.lookSaves) do
        local ok, db = pcall(read)
        if ok and type(db) == "table" then fn(db) end
    end
end

--- What the player picked: the newest pick any loaded save holds, else
--- the look players had before.
function Shared:Look(kind)
    local best, at = nil, -1
    EachSave(function(db)
        local saved = rawget(db, "lookChoices")
        if type(saved) == "table" and Valid(kind, saved[kind]) then
            local when = tonumber(saved.at) or 0
            if when > at then best, at = saved[kind], when end
        end
    end)
    if best then return best end
    return self.LOOKS[kind] and self.LOOKS[kind][1] or nil
end

--- The player picked `value` here: written to every loaded addon's save,
--- and every other addon hears it so its Settings show it. Returns true
--- when it was taken.
function Shared:SetLook(kind, value)
    if not Valid(kind, value) then return false end
    local picks = {}
    for each in pairs(self.LOOKS) do picks[each] = self:Look(each) end
    picks[kind] = value
    picks.at = (type(time) == "function" and time()) or 0
    EachSave(function(db)
        local copy = {}
        for k, v in pairs(picks) do copy[k] = v end
        db.lookChoices = copy
    end)
    self:Changed("look", kind)
    return true
end

-- Font and colors as this addon draws them, read once its save is in.
Shared.drawn = {}

--- Font or colors as drawn now. Before this addon's save loads it answers
--- the look players had before without keeping it.
function Shared:Drawn(kind)
    local kept = self.drawn[kind]
    if kept then return kept end
    local read = board.lookSaves[ADDON or "?"]
    local ok, db = pcall(read)
    if not (ok and db) then return self.LOOKS[kind] and self.LOOKS[kind][1] or nil end
    kept = self:Look(kind)
    self.drawn[kind] = kept
    return kept
end

--- True when the pick differs from what is drawn, so Settings offer Reload.
function Shared:NeedsReload(kind)
    return self:Look(kind) ~= self:Drawn(kind)
end

--- True when this client's letters are all in the clear font.
function Shared.ClearFits()
    local ok, locale = pcall(function() return GetLocale and GetLocale() end)
    return not (ok and Shared.NO_CLEAR[locale])
end

--- The font file to draw with. `house` is the font drawn before.
function Shared:FontPath(house)
    local pick = self:Drawn("font")
    if pick == "game" then
        local ok, path = pcall(function() return (ChatFontNormal:GetFont()) end)
        if ok and type(path) == "string" and path ~= "" then return path end
    elseif pick == "clear" and Shared.ClearFits() then
        return Shared.CLEAR_FONT
    end
    return house
end

Shared.recolored = setmetatable({}, { __mode = "k" })

--- Put Darker into `colors` (a Theme palette), once, in place, so tables
--- other files kept see it too. Returns true when it changed anything.
function Shared:Recolor(colors)
    if type(colors) ~= "table" or self.recolored[colors] then return false end
    if self:Drawn("colors") ~= "darker" then
        -- Warm, kept for the session: nothing to do, ever.
        if self.drawn.colors then self.recolored[colors] = true end
        return false
    end
    for key, value in pairs(self.DARKER) do
        local color = colors[key]
        if type(color) == "table" then
            color[1], color[2], color[3] = value[1], value[2], value[3]
        end
    end
    self.recolored[colors] = true
    return true
end

return Shared
