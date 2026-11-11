-- Blackthornes Tradeskills -- UI/Veil.lua
-- Putting one of the game's frames out of sight without running the game's
-- own code as this addon.
--
-- Hide and Show on a game frame run its OnHide and OnShow code right there,
-- tainted by whoever called them. For a frame Edit Mode lays out (the quest
-- tracker, the bag bar) that taint stays in Edit Mode's layout, and its next
-- update (a reload, a loading screen) reads auras as this addon and stops
-- with "Auras cannot be accessed when secret while tainted by
-- 'another addon'". So a game frame is never hidden here. It is made
-- see-through (SetAlpha) and stops taking the mouse (EnableMouse), which run
-- no game code, and both are put back as they were. Nothing is written to the
-- game's frames: what was changed is kept in this file's own table.

local _, ns = ...

local Veil = ns.NewModule("Veil")

-- How deep and how many frames to look through for ones that take the mouse.
local MOST_DEPTH = 8
local MOST_FRAMES = 600

-- [frame] = { alpha = what it was, mouse = { [frame] = { click, motion } } }
local covered = setmetatable({}, { __mode = "k" })

local function InCombat()
    local fn = _G.InCombatLockdown
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn)
    return ok and value == true
end

-- Calls frame:method(...) in a pcall; the first value, or nil.
local function Ask(frame, method, ...)
    local fn = type(frame) == "table" and frame[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, frame, ...)
    if ok then return value end
    return nil
end

-- Does the frame take clicks, and mouse-over? Read as two plain flags.
local function Mouse(frame)
    local click, motion
    if type(frame.IsMouseClickEnabled) == "function" then
        click = Ask(frame, "IsMouseClickEnabled") == true
        motion = Ask(frame, "IsMouseMotionEnabled") == true
    else
        click = Ask(frame, "IsMouseEnabled") == true
        motion = click
    end
    return click, motion
end

local function SetMouse(frame, click, motion)
    if type(frame.SetMouseClickEnabled) == "function" then
        local ok = pcall(frame.SetMouseClickEnabled, frame, click)
        return pcall(frame.SetMouseMotionEnabled, frame, motion) and ok
    end
    local enable = frame.EnableMouse
    return type(enable) == "function" and pcall(enable, frame, click or motion)
end

-- The frame and everything inside it, as far as the limits allow.
local function Each(frame, fn)
    local count = 0
    local function Visit(current, depth)
        if count >= MOST_FRAMES then return end
        count = count + 1
        fn(current)
        if depth >= MOST_DEPTH or type(current.GetChildren) ~= "function" then return end
        local ok, children = pcall(function() return { current:GetChildren() } end)
        if not ok then return end
        for _, child in ipairs(children) do
            if type(child) == "table" then Visit(child, depth + 1) end
        end
    end
    Visit(frame, 0)
end

--- Is the frame out of sight through here?
function Veil:Covers(frame)
    return covered[frame] ~= nil
end

--- Make the frame see-through and stop it and what is inside it taking the
--- mouse. Safe to call again: it then catches pieces the game added since.
--- True when all of it is done; false when a protected piece has to wait for
--- combat to end (call again then).
function Veil:Cover(frame)
    if type(frame) ~= "table" then return false end
    local state = covered[frame]
    if not state then
        state = { alpha = tonumber(Ask(frame, "GetAlpha")) or 1, mouse = setmetatable({}, { __mode = "k" }) }
        covered[frame] = state
    end
    if type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, 0) end

    local waiting = false
    local fighting = InCombat()
    Each(frame, function(piece)
        if state.mouse[piece] then return end
        local click, motion = Mouse(piece)
        if not (click or motion) then return end
        if fighting and Ask(piece, "IsProtected") then
            waiting = true
            return
        end
        if SetMouse(piece, false, false) then state.mouse[piece] = { click, motion } end
    end)
    return not waiting
end

--- Put the frame back as it was. True when done; false when a protected
--- piece has to wait for combat to end (call again then).
function Veil:Uncover(frame)
    local state = covered[frame]
    if not state then return true end
    local fighting = InCombat()
    local waiting = false
    for piece, was in pairs(state.mouse) do
        if fighting and Ask(piece, "IsProtected") then
            waiting = true
        else
            SetMouse(piece, was[1], was[2])
            state.mouse[piece] = nil
        end
    end
    if type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, state.alpha) end
    if waiting then return false end
    covered[frame] = nil
    return true
end
