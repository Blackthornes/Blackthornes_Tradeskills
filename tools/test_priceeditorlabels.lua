-- The "Your price" window's row labels (UI/PriceEditor.lua).
--
-- A player saw "Suggest..." and "How ma..." cut short, and a greyed out
-- "Use suggested" that read as broken (2026-11-05). The labels now widen to
-- the longest one; the button shows only once a price of your own is typed.

local failures = 0
local function check(name, got, want)
    if got == want then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print(("  FAIL %s: got %s, want %s"):format(name, tostring(got), tostring(want)))
    end
end

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
-- About 7 pixels a letter.
ns.Theme = { TextWidth = function(label) return #label.text * 7 end }
ns.Widgets, ns.Util = {}, {}

local chunk = assert(loadfile("UI/PriceEditor.lua"))
chunk("Blackthornes_TS", ns)
local PriceEditor = ns.PriceEditor

local function Label(text)
    local label = { text = text }
    function label:SetWidth(width) self.width = width end
    return label
end

print("")
print("row labels")

local short = { Label("Each"), Label("Total") }
PriceEditor.FitLabels(short)
check("short words keep the usual width", short[1].width, 64)

local long = { Label("Suggested"), Label("Each"), Label("How many"), Label("Total") }
local width = PriceEditor.FitLabels(long)
check("the longest sets the width", width, 9 * 7 + 8)
check("every label gets it", long[4].width, width)

local german = { Label("Vorgeschlagen"), Label("Anzahl") }
check("a longer language widens more", PriceEditor.FitLabels(german), 13 * 7 + 8)

print("")
print("the Use suggested button")
local source = io.open("UI/PriceEditor.lua"):read("*a")
check("shown only for a price of your own",
    source:find('self.reset:SetShown(line.priceBasis == "chosen")', 1, true) ~= nil, true)
check("never greyed out", source:find("self.reset:SetEnabledState", 1, true), nil)

print("")
if failures > 0 then
    print(("%d check(s) failed"):format(failures))
    os.exit(1)
end
print("all checks passed")
