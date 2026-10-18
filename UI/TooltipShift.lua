-- Blackthornes Tradeskills -- UI/TooltipShift.lua
-- Off, Shift or Always for each tooltip line the addon adds (a player asked,
-- the owner said yes, 2026-10-18). Shift: the line shows only while Shift is
-- held. Every line starts where it was, so no one's settings change: a line
-- that was on is Always and one that was off is Off, until the player picks.
--
-- The same file in all five addons (a fix to it belongs in all five). What
-- differs is each addon's own: `TooltipShift.KEYS`, the lines it has, and
-- where a line's Shift choice is kept. By default that is the account save's
-- `tooltipShift[key] = true` (never rename it); an addon that keeps settings
-- elsewhere sets `TooltipShift.Read` and `TooltipShift.Write` (Tradeskills).
-- Whether a line is on at all stays in the setting it always had.
--
-- One shared table, `_G.BlackthornesTooltipShift`, ties the copies together:
--   * "Hold Shift for more." goes on a tooltip once, however many addons held
--     a line back (`shared.hinted`, cleared when the tooltip is).
--   * One frame, the first copy's, hears Shift go down or up and redraws the
--     tooltip showing, once, only while some copy has a line on Shift.
-- Reads only; never touches a Blizzard frame beyond adding a line and a
-- HookScript on OnTooltipCleared, and `RefreshData`, the tooltip's own redraw.

local addonName, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local TooltipShift = {}
ns.TooltipShift = TooltipShift

TooltipShift.OFF = 0
TooltipShift.SHIFT = 1
TooltipShift.ALWAYS = 2

-- Shown on the Settings stepper, least shown to most.
TooltipShift.NAMES = { [0] = L["Off"], [1] = L["Shift"], [2] = L["Always"] }

-- The lines this addon has; the addon fills it in.
TooltipShift.KEYS = TooltipShift.KEYS or {}

-- The hint's grey, the game's own disabled text.
TooltipShift.HINT_COLOR = { 0.55, 0.57, 0.62 }

local shared = _G.BlackthornesTooltipShift
if type(shared) ~= "table" then
    shared = {}
    _G.BlackthornesTooltipShift = shared
end
shared.hinted = shared.hinted or setmetatable({}, { __mode = "k" })
shared.hooked = shared.hooked or setmetatable({}, { __mode = "k" })
shared.copies = shared.copies or {}
shared.copies[addonName or "?"] = TooltipShift
TooltipShift.shared = shared

--- This line's Shift choice as kept, true or false.
function TooltipShift.Read(key)
    local db = ns.db
    local kept = type(db) == "table" and db.tooltipShift
    return type(kept) == "table" and kept[key] == true
end

--- Keep this line's Shift choice. Off and Always both clear it; only a true
--- is ever written, so a save that never picks Shift gains nothing.
function TooltipShift.Write(key, on)
    local db = ns.db
    if type(db) ~= "table" then return end
    if on then
        if type(db.tooltipShift) ~= "table" then db.tooltipShift = {} end
        db.tooltipShift[key] = true
    elseif type(db.tooltipShift) == "table" then
        db.tooltipShift[key] = nil
    end
end

--- True while either Shift key is held. Read in a pcall, as every client value.
function TooltipShift.ShiftDown()
    local ok, down = pcall(function() return IsShiftKeyDown and IsShiftKeyDown() end)
    return ok and down and true or false
end

--- The stepper's value for a line: Off when its own setting is off, else
--- Shift or Always by the kept choice.
function TooltipShift:Mode(isOn, key)
    if not isOn then return self.OFF end
    if self.Read(key) then return self.SHIFT end
    return self.ALWAYS
end

--- The stepper moved. `setOn(true|false)` is the line's own on/off setter,
--- called only when that changes. Off leaves the kept Shift choice alone.
function TooltipShift:Apply(mode, key, isOn, setOn)
    local wantOn = mode ~= self.OFF
    if setOn and (isOn and true or false) ~= wantOn then setOn(wantOn) end
    if wantOn then self.Write(key, mode == self.SHIFT) end
    shared.version = (shared.version or 0) + 1
end

--- For a line that is on: may it go on the tooltip now? A line on Shift
--- shows only while Shift is held. Ask it each time the tooltip is built,
--- never keep the answer.
function TooltipShift:Shows(key)
    if not self.Read(key) then return true end
    return self.ShiftDown()
end

--- Any of this addon's lines on Shift.
function TooltipShift:AnyShift()
    for _, key in ipairs(self.KEYS) do
        if self.Read(key) then return true end
    end
    return false
end

local function ClearHint(tooltip)
    shared.hinted[tooltip] = nil
end

--- A line was held back from `tooltip`: add "Hold Shift for more." once, after
--- what the addon added. Call it after the addon's own lines.
function TooltipShift:Held(tooltip)
    if type(tooltip) ~= "table" or shared.hinted[tooltip] then return end
    if not shared.hooked[tooltip] then
        local ok = pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", ClearHint)
        if not ok then return end
        shared.hooked[tooltip] = true
    end
    shared.hinted[tooltip] = true
    local color = self.HINT_COLOR
    pcall(tooltip.AddLine, tooltip, L["Hold Shift for more."], color[1], color[2], color[3])
    pcall(function() if tooltip:IsShown() then tooltip:Show() end end)
end

--- Any copy, in any Blackthornes addon, with a line on Shift.
function shared.AnyShift()
    for _, copy in pairs(shared.copies) do
        local ok, any = pcall(copy.AnyShift, copy)
        if ok and any then return true end
    end
    return false
end

--- Shift went down or up: redraw the tooltip showing, once, so its Shift
--- lines come and go. Only while some line is on Shift; nothing else moves.
function shared.OnModifier(key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not shared.AnyShift() then return end
    local tooltip = _G.GameTooltip
    if type(tooltip) ~= "table" then return end
    pcall(function()
        if tooltip:IsShown() and tooltip.RefreshData then tooltip:RefreshData() end
    end)
end

if not shared.frame and type(CreateFrame) == "function" then
    local ok, frame = pcall(CreateFrame, "Frame")
    if ok and frame then
        shared.frame = frame
        pcall(frame.RegisterEvent, frame, "MODIFIER_STATE_CHANGED")
        frame:SetScript("OnEvent", function(_, _, key)
            -- The newest handler any copy left, so a fix in one reaches all.
            local handler = _G.BlackthornesTooltipShift.OnModifier
            if handler then handler(key) end
        end)
    end
end

