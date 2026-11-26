-- Logic/Butler.lua's Disenchanter and SetDisenchanter outside WoW.
--
-- Butler's Set Up Butler card (2026-11-26) reads and types the
-- disenchanter on the Mail page. What must hold:
--   1. An empty box reads as nil; a typed name comes back trimmed.
--   2. SetDisenchanter writes `disenchanterName` as the Mail page does,
--      and the mail panel is told.
--   3. The character playing is refused and nothing is written.
--   4. A name that isn't text is refused; nil empties the box.
--   5. A broken settings module never raises.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local settings = { disenchanterName = "" }
ns.Config = {
  Get = function(_, key) return settings[key] end,
  Set = function(_, key, value) settings[key] = value end,
}
local refreshed = 0
ns.QueueMailPanel = { Refresh = function() refreshed = refreshed + 1 end }
ns.QueueMail = { IsPlayingName = function(_, name) return name == "Ana Stone" end }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Butler.lua"))
chunk("Blackthornes_TS", ns)
local Butler = ns.Butler

local failures = 0
local function check(label, got, want)
  if got == want then
    print("  ok   " .. label)
  else
    failures = failures + 1
    print(("  FAIL %s: got %s, want %s"):format(label, tostring(got), tostring(want)))
  end
end

-- 1.
check("an empty box is nil", Butler:Disenchanter(), nil)
settings.disenchanterName = "  Mira Vale "
check("a typed name, trimmed", Butler:Disenchanter(), "Mira Vale")

-- 2.
settings.disenchanterName = ""
check("types the name", Butler:SetDisenchanter(" Mira Vale"), true)
check("saved trimmed", settings.disenchanterName, "Mira Vale")
check("the mail panel is told", refreshed, 1)

-- 3.
local ok = Butler:SetDisenchanter("Ana Stone")
check("the one playing is refused", ok, false)
check("nothing written for the one playing", settings.disenchanterName, "Mira Vale")

-- 4.
check("a number is refused", Butler:SetDisenchanter(42), false)
check("nil empties the box", Butler:SetDisenchanter(nil), true)
check("the box is empty", settings.disenchanterName, "")

-- 5.
ns.Config.Get = function() error("broken") end
ns.Config.Set = function() error("broken") end
check("a broken read is nil", Butler:Disenchanter(), nil)
check("a broken write is false", (Butler:SetDisenchanter("Mira Vale")), false)

if failures > 0 then error(failures .. " check(s) failed") end
print("All Butler disenchanter checks passed.")
