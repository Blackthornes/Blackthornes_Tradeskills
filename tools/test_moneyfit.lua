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
check("12g 5s 0c in two", Plain(Util.FormatMoney(120500, { parts = 2 })), "12g 5s")
check("99s 60c in one carries to gold", Plain(Util.FormatMoney(9960, { parts = 1 })), "1g")
check("silver and copper in two stay whole", Plain(Util.FormatMoney(3456, { parts = 2 })), "34s 56c")
check("a loss keeps its sign", Plain(Util.FormatMoney(-AMOUNT, { parts = 2 })):find("12g 35s", 1, true) ~= nil, true)
check("without parts nothing changes", Plain(Util.FormatMoney(AMOUNT)), "12g 34s 56c")

print("")
print(("%d passed, %d failed"):format(passed, failed))
assert(failed == 0, "money fitting checks failed")
