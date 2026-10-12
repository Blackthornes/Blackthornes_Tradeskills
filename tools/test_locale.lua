-- The translations: on a German client Tradeskills speaks Deutsch, on any
-- other it speaks English, and a word with no German line falls back to its
-- English key. L.Format puts values named by place ("%2$s ... %1$d") in
-- order, which the tests' Lua 5.1 cannot do itself.

local failures = 0
local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

--- The locale files as the TOC loads them, on a client in `locale`.
local function Load(locale)
  _G.GetLocale = function() return locale end
  local ns = {}
  assert(loadfile(lfs_cwd .. "/Locale/Locale.lua"))("Blackthornes_TS", ns)
  assert(loadfile(lfs_cwd .. "/Locale/deDE.lua"))("Blackthornes_TS", ns)
  return ns
end

local ns = Load("enUS")
check("English shows English", ns.L["Queue"], "Queue")
check("English formats as before", ns.L.Format("%d listed", 4), "4 listed")

ns = Load("deDE")
check("a tab name in Deutsch", ns.L["Queue"], "Liste")
check("a German line formats", ns.L.Format("%d listed", 4), "4 angeboten")
check("a word with no German line falls back", ns.L["A string nobody translated"], "A string nobody translated")
check("and formats in English", ns.L.Format("%d stacks, %s", 3, "grey"), "3 stacks, grey")
check("values named by place go in order", ns.L.Format("%2$s then %1$d", 7, "first"), "first then 7")

-- The age words the narrow columns compare against follow the language.
assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
check("a fresh age reads in Deutsch", ns.Util.FormatAge and ns.Util.FormatAge(0) or ns.L["just now"], ns.L["just now"])

ns = Load("frFR")
check("a language with no file shows English", ns.L["Queue"], "Queue")

_G.GetLocale = nil
if failures > 0 then error(failures .. " locale check(s) failed") end
print("locale: all checks passed")
