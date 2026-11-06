-- The Snipe tab's strip, measured in the client's language (2026-11-06).
--
-- What must hold:
--   1. The label column is as wide as the longest label, German included,
--      and never past its most.
--   2. Watch: and List: share one width from their longest choice, list
--      names included, between the least and the most.
--   3. Column heads are measured, so a long German head can grow the row.

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
-- A stand-in for the client's font: six pixels a letter.
ns.Theme = { MeasureText = function(_, text) return #text * 6 end }
ns.Util = {}

-- The German words, read line by line from the locale file.
local de = {}
for line in io.lines(lfs_cwd .. "/Locale/deDE.lua") do
    local k, v = line:match('^L%["(.-)"%]%s*=%s*"(.-)"%s*$')
    if k then de[k] = v end
end
ns.L = setmetatable({ Format = string.format }, { __index = function(_, k) return de[k] or k end })

assert(loadfile(lfs_cwd .. "/UI/SnipeView.lua"))("Blackthornes_TS", ns)
local View = ns.SnipeView
local L = ns.L

assert(L["My Lists"] == "Meine Listen" and L["List:"] == "Liste:", "German words are read")

-- 1. One label column.
local labels = { L["Spending Cap:"], L["Snipe Below:"], L["Watch:"], L["List:"] }
local widest = 0
for _, text in ipairs(labels) do widest = math.max(widest, #text * 6) end
local column = View.LabelColumn(labels)
assert(column == math.min(170, widest), "the column is the longest German label")
assert(View.LabelColumn({ string.rep("x", 80) }) == 170, "never past its most")
assert(View.LabelColumn({}) == 90, "nothing measured keeps a sensible width")

-- 2. One width for Watch: and List:.
local options = {
    { text = L["Priced Items"] }, { text = L["To Disenchant"] },
    { text = L["Below Vendor"] }, { text = L["My Lists"] },
    { text = L["All Lists"] }, { text = "Kräuter für Alchemie" },
}
local longest = 0
for _, option in ipairs(options) do longest = math.max(longest, #option.text * 6) end
local width = View.ChoiceWidth(options)
assert(width == math.max(140, math.min(240, longest + 30)), "the longest choice and its arrow")
assert(View.ChoiceWidth({ { text = string.rep("y", 90) } }) == 240, "a very long list name is capped")
assert(View.ChoiceWidth({ { text = "A" } }) == 140, "never narrower than the least")

-- 3. Heads are measured.
local most = L["Most I'll Pay:"]:gsub("[:：]%s*$", "")
assert(View.HeadWidth(most) == #most * 6, "a head is measured in the client's words")

print("test_snipelayout: all passed")
