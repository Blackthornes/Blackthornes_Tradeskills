-- The Snipe strip's boxes (UI/SnipeView.lua LayStrip, UI/PriceEditor.lua).
--
-- 2026-11-06: LayStrip called ClearAllPoints on the Spending Cap money
-- boxes, which had none. The drawer's build stopped there, so the Snipe
-- labels showed on every auction house tab and the tabs after it broke.
-- Every method LayStrip calls on a box must be one the box has.

local failures = 0
local function check(name, ok)
    if ok then print("  ok   " .. name) else failures = failures + 1; print("  FAIL " .. name) end
end

-- Strict frames: only the methods a real frame has that these files use.
local function Frame()
    local f = {}
    for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetHeight", "SetWidth", "SetShown",
        "Show", "Hide", "SetAlpha", "SetScript", "SetText", "SetValue", "GetValue" }) do
        f[m] = function() end
    end
    return f
end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.Theme = { CreateLabel = function() return Frame() end, TextWidth = function() return 10 end }
ns.Widgets = { CreateNumberBox = function() return Frame() end }
ns.Util = { SplitMoney = function() return 0, 0, 0 end }
assert(loadfile("UI/PriceEditor.lua"))("Blackthornes_TS", ns)
local money = ns.PriceEditor.MoneyBoxes(Frame(), function() end)

print("")
print("snipe strip boxes")

local source = assert(io.open("UI/SnipeView.lua")):read("*a")
local lay = source:match("function SnipeView:LayStrip%(%)(.-)\nend\n")
check("LayStrip found", lay ~= nil)
local used = {}
for loop in (lay or ""):gmatch("for _, box in ipairs%b()%s*do(.-)end") do
    for method in loop:gmatch("box:(%w+)%(") do used[method] = true end
end
check("LayStrip calls methods on its boxes", next(used) ~= nil)
for method in pairs(used) do
    check("money boxes answer " .. method, type(money[method]) == "function")
end

print("")
if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all checks passed")
