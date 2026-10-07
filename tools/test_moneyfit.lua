-- Money in a narrow cell, outside WoW.
--
-- What must hold:
--   1. An amount that fits keeps every coin.
--   2. One that does not drops to its two largest coins, then its largest,
--      rounded to the last coin shown, and never ends in "...".
--   3. A label that cannot be measured keeps every coin.
--   4. Coins left out stay out when they come to nothing ("12g", not
--      "12g 0s"), and rounding up can carry into the next coin.

-- Tests share one Lua state, so every global replaced here is put back,
-- including the ones that were not set at all.
local GLOBALS = { "CreateFrame" }
local saved = {}
for _, key in ipairs(GLOBALS) do saved[key] = _G[key] end

local function noop() end

-- Util makes its worker frame as it loads.
CreateFrame = function()
    return setmetatable({}, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return noop end
    end })
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
assert(loadfile(lfs_cwd .. "/UI/Theme.lua"))("Blackthornes_TS", ns)

for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end

local Util, Theme = ns.Util, ns.Theme

local passed, failed = 0, 0

local function check(label, got, want)
    local ok = got == want
    if ok then passed = passed + 1 else failed = failed + 1 end
    print(string.format("  %-52s %-14s %s", label, tostring(got), ok and "ok" or
        ("WRONG, wanted " .. tostring(want))))
end

local function Plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- A label six pixels a character, colour codes not drawn.
local function Label(width, measurable)
    local label = { text = "" }
    function label:SetText(text) self.text = text end
    function label:GetWidth() return width end
    if measurable ~= false then
        function label:GetStringWidth() return #Plain(self.text) * 6 end
    else
        function label:GetStringWidth() error("secret") end
    end
    return label
end

local AMOUNT = 12 * 10000 + 34 * 100 + 56     -- 12g 34s 56c

print("")
print("a money cell")

local label = Label(200)
Theme.SetMoneyText(label, AMOUNT)
check("with room, every coin", Plain(label.text), "12g 34s 56c")

label = Label(50)
Theme.SetMoneyText(label, AMOUNT)
check("narrower, the two largest, rounded", Plain(label.text), "12g 35s")

label = Label(20)
Theme.SetMoneyText(label, AMOUNT)
check("narrower still, gold alone", Plain(label.text), "12g")

label = Label(20, false)
Theme.SetMoneyText(label, AMOUNT)
check("a label that cannot be measured keeps them all", Plain(label.text), "12g 34s 56c")

label = Label(0)
Theme.SetMoneyText(label, AMOUNT)
check("one not laid out yet keeps them all", Plain(label.text), "12g 34s 56c")

label = Label(20)
Theme.SetMoneyText(label, nil)
check("no amount is the dash", Plain(label.text), "--")

print("")
print("fewer coins")

check("12g 0s 0c in one coin", Plain(Util.FormatMoney(120000, { parts = 1 })), "12g")
check("12g 5s 0c in two", Plain(Util.FormatMoney(120500, { parts = 2 })), "12g 05s")
check("99s 60c in one carries to gold", Plain(Util.FormatMoney(9960, { parts = 1 })), "1g")
check("silver and copper in two stay whole", Plain(Util.FormatMoney(3456, { parts = 2 })), "34s 56c")
check("a loss keeps its sign", Plain(Util.FormatMoney(-AMOUNT, { parts = 2 })):find("12g 35s", 1, true) ~= nil, true)
check("without parts nothing changes", Plain(Util.FormatMoney(AMOUNT)), "12g 34s 56c")

print("")
print("one shape for every amount (Ezmode's request, 2026-10-07)")

check("every coin below gold shows, two digits", Plain(Util.FormatMoney(10500)), "1g 05s 00c")
check("no silver still shows its 00s", Plain(Util.FormatMoney(10053)), "1g 00s 53c")
check("a round amount of gold", Plain(Util.FormatMoney(30000)), "3g 00s 00c")
check("silver alone keeps its copper", Plain(Util.FormatMoney(800)), "8s 00c")
check("silver is not padded when it leads", Plain(Util.FormatMoney(512)), "5s 12c")
check("copper alone stays as it is", Plain(Util.FormatMoney(45)), "45c")
check("nothing at all", Plain(Util.FormatMoney(0)), "0c")
check("a loss pads the same way", Plain(Util.FormatMoney(-10500)), "-1g 05s 00c")
check("thousands of gold keep their commas", Plain(Util.FormatMoney(12345600)), "1,234g 56s 00c")
check("short still drops the small coins past 100g", Plain(Util.FormatMoney(1234567, { short = true })), "123g")
check("short pads under 100g", Plain(Util.FormatMoney(120005, { short = true })), "12g 00s 05c")

print("")
print("an item name on a row is never cut off")

local name = Label(120)
function name:SetFont(_, size) self.size = size end
function name:SetWordWrap(wrap) self.wrap = wrap end
Theme.SetRowName(name, "Camp Chair")
check("one that fits keeps its line", name.wrap, false)
check("in the row's size", name.size, Theme.sizes.small)
Theme.SetRowName(name, "Deviate Scale Cloak of the Monkey")
check("a long one wraps rather than ending in ...", name.wrap, true)
check("in the smaller size", name.size, Theme.sizes.tiny)
check("and keeps every word", name.text, "Deviate Scale Cloak of the Monkey")
Theme.SetRowName(name, "Camp Chair")
check("the next short one is back on one line", name.wrap, false)
check("in the row's size again", name.size, Theme.sizes.small)

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "money fitting checks failed")
