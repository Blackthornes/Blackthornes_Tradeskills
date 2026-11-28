-- The step box (UI/TravelCard.lua, the same file in all five addons, and so
-- is this test): Your Way There as one small see-through row (the owner
-- said build it, 2026-11-24).
--
-- The file is loaded by itself with a small world of its own, so the test
-- runs the same in every addon.
--
-- What must hold:
--   1. It shows only the step you are on, how far, "Step 2 of 4" and about
--      how long.
--   2. It hangs under the addon's panel when one shows, as wide as it and
--      with no close gem; else under the big arrow; else where it was put.
--      The close gem shows whenever it is not under a panel.
--   3. Its small dial points while the arrow does, and shows a dot when
--      there is no way to point.
--   4. The glass is thin until the mouse comes; the buttons wait for it.
--   5. The big arrow keeps only its name while the box shows.
--   6. The close gem puts it away for this place only.

-- Tests share one Lua state: every global set here is put back at the end.
local GLOBALS = { "CreateFrame", "UIParent", "InCombatLockdown" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local failures = 0
local function check(label, ok, detail)
    if ok then return end
    failures = failures + 1
    print(("  FAIL %s%s"):format(label, detail and ("  -> " .. tostring(detail)) or ""))
end

-- A frame, texture or label that takes any call and remembers a few.
local function Piece()
    local piece = { shown = true, text = "", width = 250 }
    function piece:Show() self.shown = true end
    function piece:Hide() self.shown = false end
    function piece:SetShown(on) self.shown = on and true or false end
    function piece:IsShown() return self.shown end
    function piece:SetText(text) self.text = tostring(text or "") end
    function piece:GetText() return self.text end
    function piece:GetStringWidth() return #self.text * 6 end
    function piece:GetStringHeight() return 12 end
    function piece:SetWidth(width) self.width = width end
    function piece:GetWidth() return self.width end
    function piece:SetHeight(height) self.height = height end
    function piece:SetAlpha(alpha) self.alpha = alpha end
    function piece:GetScale() return 1 end
    function piece:GetFrameLevel() return 1 end
    function piece:IsMouseOver() return false end
    function piece:SetPoint(...) self.point = { ... } end
    function piece:CreateTexture() return Piece() end
    function piece:CreateFontString() return Piece() end
    function piece:SetScript(name, fn) self[name] = fn end
    function piece:HookScript(name, fn) self[name] = fn end
    return setmetatable(piece, { __index = function() return function() end end })
end

CreateFrame = function() local frame = Piece() frame.shown = true return frame end
UIParent = Piece()
InCombatLockdown = function() return false end

local hang, dial
local db = {}
local stopped = false
local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.Theme = {
    Fill = function() return Piece() end,
    Border = function() return {} end,
    CreateLabel = function() return Piece() end,
    Unpack = function() return 1, 1, 1, 1 end,
    sizes = { normal = 13, small = 11 },
}
ns.Widgets = { CreateButton = function() return Piece() end }
ns.Titanforged = { CloseGem = function() return Piece() end }
ns.Travel = {
    Host = {
        DB = function() return db end,
        Show = function(zone) return zone end,
        State = function() return nil end,
        Here = function() return nil end,
        Hang = function() return hang end,
        Dial = function() return dial end,
    },
    ShortName = function(name) return name end,
    StepWords = function(step) return "Go to " .. tostring(step.to and step.to.name) end,
    Minutes = function(plan) return math.max(1, math.floor((plan.cost or 0) / 60 + 0.5)) end,
    StopTrip = function() stopped = true end,
}

local chunk = assert(loadfile(lfs_cwd .. "/UI/TravelCard.lua"))
chunk("Blackthornes_Test", ns)
local TravelCard = ns.TravelCard

local function Step(kind, name, zone) return { kind = kind, to = { name = name, zone = zone } } end
local plan = { key = "outhouse", done = 1, cost = 600,
    steps = { Step("zeppelin", "Grom'gol"), Step("fly", "Kargath"), Step("walk", "Wooden Outhouse", "Searing Gorge") } }
local trip = { plan = plan, index = 2, count = 4, step = plan.steps[1],
    line = "Take the zeppelin to Grom'gol", small = "" }

-- 1. One step, with the arrow's words. Nothing to hang from: free.
TravelCard:Update({ trip = trip, mode = "point", turn = 0, place = trip.line, note = "120 yd" })
local frame = TravelCard.frame
check("it shows on a trip", frame and frame:IsShown())
check("the step you are on", TravelCard.title:GetText() == "Take the zeppelin to Grom'gol", TravelCard.title:GetText())
check("how far, from the arrow", TravelCard.sub:GetText() == "120 yd", TravelCard.sub:GetText())
local count = TravelCard.count:GetText()
check("which step and about how long", count:find("Step 2 of 4", 1, true) and count:find("10", 1, true), count)
check("free, with the close gem", TravelCard.where == "free" and TravelCard.close:IsShown(), TravelCard.where)

-- 3. The small dial.
check("the small dial points", TravelCard.blade:IsShown() and not TravelCard.dot:IsShown())
TravelCard:Update({ trip = trip, mode = "trip" })
check("no way to point: a dot", TravelCard.dot:IsShown() and not TravelCard.blade:IsShown())
check("no arrow words: the step's own small line", TravelCard.sub:GetText() == "Get on when it stops",
    TravelCard.sub:GetText())

-- 2. Under the big arrow, then under the panel, then back.
local dialFrame = Piece()
dial = { frame = dialFrame, dial = Piece() }
TravelCard:Update({ trip = trip, mode = "trip" })
check("under the big arrow", TravelCard.where == "dial" and TravelCard.anchor == dial.dial, TravelCard.where)
check("with its close gem", TravelCard.close:IsShown())
hang = Piece()
hang.width = 270
TravelCard:Update({ trip = trip, mode = "trip" })
check("under the panel", TravelCard.where == "panel" and TravelCard.anchor == hang, TravelCard.where)
check("as wide as the panel", TravelCard.width == 270, TravelCard.width)
check("no close gem under the panel", not TravelCard.close:IsShown())
hang:Hide()
TravelCard:Update({ trip = trip, mode = "trip" })
check("panel put away: back under the arrow", TravelCard.where == "dial", TravelCard.where)
dialFrame:Hide()
TravelCard:Update({ trip = trip, mode = "trip" })
check("arrow hidden too: free again", TravelCard.where == "free", TravelCard.where)

-- 4. See-through.
check("thin glass while the mouse is away", not TravelCard.solid and TravelCard.glass == TravelCard.GLASS_CLEAR
    and TravelCard.GLASS_CLEAR < 0.5, TravelCard.glass)
check("buttons wait for the mouse", not TravelCard.stop:IsShown() and not TravelCard.show:IsShown())
TravelCard:SetSolid(true)
check("solid glass and the buttons on the mouse", TravelCard.glass == TravelCard.GLASS_SOLID
    and TravelCard.stop:IsShown() and TravelCard.show:IsShown())
TravelCard:Left()
check("mouse gone: thin again", not TravelCard.solid and not TravelCard.stop:IsShown())

-- 5. The big arrow's words.
local d, p, n = TravelCard:Words({ trip = trip })
check("the arrow's words step aside", d == "" and p == "" and n == "")
check("no trip: the arrow speaks", TravelCard:Words({}) == nil)

-- 6. The close gem, then Stop.
TravelCard:Close()
TravelCard:Update({ trip = trip, mode = "trip" })
check("closed for this place", not frame:IsShown())
check("the arrow speaks again", TravelCard:Words({ trip = trip }) == nil)
check("closing keeps the trip", not stopped)
TravelCard:Update({ trip = { plan = { key = "elsewhere", steps = plan.steps, done = 0 } }, mode = "trip" })
check("a new place brings it back", frame:IsShown())
TravelCard:Stop()
check("Stop ends the trip", stopped and not frame:IsShown())
TravelCard:Update({})
check("no trip: hidden", not frame:IsShown())

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

if failures > 0 then error(string.format("%d step box check(s) failed", failures)) end
print("  stepbox: all checks passed")
