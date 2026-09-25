-- Logic/SkillUp.lua outside WoW.
--
-- The part that cannot be tested here is whether this client reports a
-- difficulty at all -- that needs the game, and /bts skillup is what asks it.
-- What IS testable is everything that happens once an answer arrives: which
-- source wins, what an unmappable value does, and which crafts earn a star.

time = function() return 1000 end

local ns = {}

ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
  function() end, function() end, function() end, function() end

local minProfit = 0
ns.Config = { Get = function(_, key) if key == "minProfit" then return minProfit end end }

-- Nothing global exists unless a case below puts it there.
local present = {}
ns.Util = {
  HasFunction = function(path) return present[path] == true end,
  Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
  FormatMoney = function(v) return tostring(v) end,
}

local chunk = assert(loadfile(lfs_cwd .. "/Logic/SkillUp.lua"))
chunk("Blackthornes_TS", ns)

local SkillUp = ns.SkillUp
local failures = 0

local function check(label, got, want)
  if got ~= want then
    failures = failures + 1
    print(string.format("  FAIL  %-52s got %s, wanted %s",
      label, tostring(got), tostring(want)))
  else
    print(string.format("  ok    %-52s %s", label, tostring(got)))
  end
end

print("\nreading a difficulty")

-- A client that answers in words, which is how the classic list reports it.
check("word 'optimal'", (SkillUp:Read(1, { relativeDifficulty = "optimal" })), "optimal")
check("word 'Trivial', any case", (SkillUp:Read(1, { relativeDifficulty = "Trivial" })), "trivial")

-- A client that answers with the modern enum. Mapped by NAME: the numbers are
-- read out of the client's own enum rather than assumed.
Enum = { TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 } }
check("enum value 0 -> optimal", (SkillUp:Read(1, { relativeDifficulty = 0 })), "optimal")
check("enum value 3 -> trivial", (SkillUp:Read(1, { relativeDifficulty = 3 })), "trivial")

-- The same number with no enum to read it against. Guessing here is how every
-- row in the list ends up wearing the wrong colour with nothing to show it.
Enum = nil
check("number with no enum is refused", (SkillUp:Read(1, { relativeDifficulty = 2 })), nil)

-- ...and the raw value is kept, because that is the thing worth reporting.
SkillUp:BeginCapture()
SkillUp:Read(1, { relativeDifficulty = 2 })
local capture = SkillUp:EndCapture()
check("the unmappable value is recorded", capture.unmapped.relativeDifficulty, "2 (number)")

-- difficulty is tried after relativeDifficulty, so a client carrying only the
-- second one is still read.
check("falls through to .difficulty", (SkillUp:Read(1, { difficulty = "medium" })), "medium")
check("nothing at all", (SkillUp:Read(1, {})), nil)

local _, source = SkillUp:Read(1, { relativeDifficulty = "easy", difficulty = "optimal" })
check("first source wins", source, "relativeDifficulty")

print("\ncapturing into the cache")

SkillUp:BeginCapture()

local stored = SkillUp:Capture(7, { name = "Bolt of Linen", relativeDifficulty = "optimal" })
check("tier stored", stored.tier, "optimal")

-- A profession window that has just opened answers nothing for a moment.
-- Dropping a good reading for that would make the stars flicker.
local kept = SkillUp:Capture(7, { name = "Bolt of Linen" }, nil, stored)
check("a silent client keeps what was known", kept, stored)

local counted = SkillUp:EndCapture()
check("attempts counted", counted.attempted, 2)
check("answers counted", counted.answered, 1)

print("\nwhich crafts earn a star")

local function analysis(tier, profit, priceable)
  return {
    priceable = priceable ~= false,
    profit = profit,
    skillUp = tier and { tier = tier } or nil,
  }
end

check("orange and in profit", SkillUp:IsWorthIt(analysis("optimal", 500)), true)
check("yellow and in profit", SkillUp:IsWorthIt(analysis("medium", 500)), true)
check("green is not marked", SkillUp:IsWorthIt(analysis("easy", 500)), false)
check("grey is not marked", SkillUp:IsWorthIt(analysis("trivial", 500)), false)
check("orange at a loss", SkillUp:IsWorthIt(analysis("optimal", -500)), false)
check("orange at exactly nothing", SkillUp:IsWorthIt(analysis("optimal", 0)), false)
check("no difficulty known", SkillUp:IsWorthIt(analysis(nil, 500)), false)
check("cannot be priced", SkillUp:IsWorthIt(analysis("optimal", 500, false)), false)

-- The minimum profit setting is the player's own answer to what is worth their
-- materials, so a star respects it rather than marking anything above zero.
minProfit = 5000
check("under the minimum profit", SkillUp:IsWorthIt(analysis("optimal", 500)), false)
check("over the minimum profit", SkillUp:IsWorthIt(analysis("optimal", 9000)), true)
minProfit = 0

print("\nreadings taken at a lower skill")

-- No profession API in this stub, so no current level can be read: with
-- nothing to compare against, a reading is never called stale.
local recipe = { skillLineID = 164, skillUp = { tier = "optimal", skill = 100 } }
check("no level to compare against", SkillUp:GetForRecipe(1, recipe).stale, nil)

SkillUp.levels = { [164] = 140 }
SkillUp.levelsAt = time()
check("skill has risen since the reading", SkillUp:GetForRecipe(1, recipe).stale, true)

SkillUp.levels = { [164] = 100 }
check("same skill as the reading", SkillUp:GetForRecipe(1, recipe).stale, nil)

check("no reading at all", SkillUp:GetForRecipe(1, { skillLineID = 164 }), nil)

print("")
if failures > 0 then
  error(string.format("%d skill-up check(s) failed", failures))
end
print(string.format("  all skill-up checks passed"))
print("")
