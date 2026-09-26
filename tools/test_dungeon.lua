-- Lua errors inside a dungeon (Trent asked, 2026-09-26).
--
-- Inside an instance the game can hand an addon a value it will not let the
-- addon read: type() answers honestly, but comparing, joining, formatting or
-- matching it raises, in the addon's own code. These are the places that met
-- one during ordinary dungeon play, and what each must do instead: carry on
-- quietly, as if the value were not there.
--
-- Plain Lua cannot make a real string refuse `==`, so the stand-in below
-- raises on everything else, and the unit-token comparison is checked in the
-- source. Every suite shares one Lua state: whatever this file replaces, it
-- puts back.

local failures = 0
local function check(ok, what)
  if not ok then failures = failures + 1; print("FAIL " .. what) end
end

local function Secret(what)
  local function refuse(verb)
    return function()
      error(("attempt to %s a secret %s value, while execution tainted by 'Blackthornes_TS'")
        :format(verb, what), 0)
    end
  end
  return setmetatable({}, {
    __index = refuse("index"), __concat = refuse("concatenate"),
    __add = refuse("perform arithmetic on"), __sub = refuse("perform arithmetic on"),
    __lt = refuse("compare"), __le = refuse("compare"), __tostring = refuse("format"),
  })
end

local function Source(path)
  local handle = assert(io.open(lfs_cwd .. "/" .. path, "r"))
  local text = handle:read("*a")
  handle:close()
  return text
end

-- Makes string.match refuse one particular text, the way it refuses a secret
-- string. Both `text:match(...)` and `string.match(text, ...)` go through it.
local realMatch = string.match
local function RefuseMatching(text)
  string.match = function(s, ...)
    if s == text then error("attempt to index a secret string value", 0) end
    return realMatch(s, ...)
  end
end
local function RestoreMatching() string.match = realMatch end

--------------------------------------------------------------------------------
-- The cast bar: UNIT_SPELLCAST_* fire for every unit in the dungeon.
--------------------------------------------------------------------------------

do
  local src = Source("UI/CastBarOnTop.lua")
  local outside = src:gsub("%-%-[^\n]*", ""):gsub("local function IsPlayer%(unit%).-\nend\n", "")
  check(not outside:find('unit%s*[~=]=%s*"player"'),
    "the cast bar never compares a unit token outside IsPlayer")
  check(src:find("not IsPlayer%(unit%)") ~= nil, "both cast handlers ask IsPlayer")

  local ns = {}
  ns.NewModule = function(name) local m = { RegisterEvent = function() end }; ns[name] = m; return m end
  ns.RegisterCommand = function() end
  local savedCast = UnitCastingInfo
  UnitCastingInfo = function() error("attempt to compare a secret boolean value", 0) end
  assert(loadfile(lfs_cwd .. "/UI/CastBarOnTop.lua"))("Blackthornes_TS", ns)
  local CastBar = ns.CastBarOnTop
  check(CastBar.IsPlayer("player") == true, "the player's own cast is the player")
  check(CastBar.IsPlayer("party1") == false, "a party member's is not")
  local ok, crafting = pcall(CastBar.IsCrafting, CastBar)
  check(ok and crafting == false, "a cast the game will not describe is not a craft, and does not raise")
  UnitCastingInfo = savedCast
end

--------------------------------------------------------------------------------
-- The sale alarm: CHAT_MSG_SYSTEM lines arrive in dungeons.
--------------------------------------------------------------------------------

do
  local ns = {}
  ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
  ns.RegisterEvent = function() return true end
  ns.RegisterCommand = function() end
  ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
  ns.Config = { Get = function() return nil end }
  ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
  local savedSold = ERR_AUCTION_SOLD_S
  ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
  assert(loadfile(lfs_cwd .. "/Logic/SaleAlarm.lua"))("Blackthornes_TS", ns)
  local SaleAlarm = ns.SaleAlarm

  check(SaleAlarm:MatchSoldLine("A buyer has been found for your auction of Linen Cloth.") == "Linen Cloth",
    "a readable sold line still matches")

  local line = "Dungeon difficulty set to Normal."
  RefuseMatching(line)
  local ok, item = pcall(SaleAlarm.MatchSoldLine, SaleAlarm, line)
  RestoreMatching()
  check(ok and item == nil, "an unreadable system line is not a sale, and does not raise")
  ERR_AUCTION_SOLD_S = savedSold
end

--------------------------------------------------------------------------------
-- The craft progress bar: read every frame while it shows.
--------------------------------------------------------------------------------

do
  local ns = { Theme = {} }
  ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
  ns.CastBarOnTop = { IsCrafting = function() return true end }
  local savedCast, savedTime, savedCreate, savedTS = UnitCastingInfo, GetTime, CreateFrame, C_TradeSkillUI
  GetTime = function() return 10 end
  C_TradeSkillUI = nil
  CreateFrame = function() return { SetScript = function() end } end
  UnitCastingInfo = function() return Secret("string"), "", nil, 9000, 13000, true end
  assert(loadfile(lfs_cwd .. "/UI/CraftProgress.lua"))("Blackthornes_TS", ns)

  local ok, cast = pcall(ns.CraftProgress.Read, ns.CraftProgress)
  check(ok and cast == nil, "a cast name the game will not show means no bar, not an error each frame")

  UnitCastingInfo = function() return "Light Leather", "", nil, 9000, 13000, true end
  ok, cast = pcall(ns.CraftProgress.Read, ns.CraftProgress)
  check(ok and cast and cast.name == "Light Leather", "a readable craft still shows")

  UnitCastingInfo, GetTime, CreateFrame, C_TradeSkillUI = savedCast, savedTime, savedCreate, savedTS
end

--------------------------------------------------------------------------------
-- Item tooltips: loot, rolls and bags are hovered all through a dungeon.
--------------------------------------------------------------------------------

do
  local ns = {}
  ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
  ns.RegisterCommand = function() end
  ns.Print, ns.PrintRaw = function() end, function() end
  ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
  ns.Util = { HasFunction = function() return false end }
  ns.Config = { Get = function() return nil end }
  assert(loadfile(lfs_cwd .. "/UI/ItemTooltip.lua"))("Blackthornes_TS", ns)
  local Tip = ns.ItemTooltip

  local link = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
  check(Tip.ItemIDFromLink(link) == 2589, "a readable link still gives its item")
  RefuseMatching(link)
  local ok, id = pcall(Tip.ItemIDFromLink, link)
  RestoreMatching()
  check(ok and id == nil, "an unreadable link is no item, and does not raise")

  check(Tip.PlainID(2589) == 2589, "a plain item ID passes")
  check(Tip.PlainID(Secret("number")) == nil, "an unreadable one does not")
  check(Tip.PlainID(0) == nil, "nor does zero")

  local realDecorate = Tip.Decorate
  Tip.Decorate = function(self) self.writing = true; error("attempt to compare a secret number value", 0) end
  local okHover, outcome = pcall(Tip.OnTooltip, Tip, {}, {}, "post", nil)
  check(okHover and outcome == "noitem", "a tooltip that raises costs the price line, not a Lua error")
  check(Tip.writing == false, "and the next tooltip still gets decorated")
  Tip.Decorate = realDecorate
end

--------------------------------------------------------------------------------
-- The character key: computed on login or /reload, which can be in a dungeon.
--------------------------------------------------------------------------------

do
  local ns = {}
  ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
  ns.RegisterCommand = function() end
  ns.Util = {}
  local savedName, savedRealm = UnitName, GetRealmName
  UnitName = function() return Secret("string") end
  GetRealmName = function() return "Forever" end
  assert(loadfile(lfs_cwd .. "/Core/Config.lua"))("Blackthornes_TS", ns)
  local ok, key = pcall(ns.Config.GetCharacterKey, ns.Config)
  check(ok and key == "Unknown-Forever", "an unreadable name does not raise: " .. tostring(ok and key))

  ns.Config.characterKey = nil
  UnitName = function() return "Blackthornez" end
  check(ns.Config:GetCharacterKey() == "Blackthornez-Forever", "a readable name is used as before")
  UnitName, GetRealmName = savedName, savedRealm
end

if failures > 0 then error(failures .. " dungeon check(s) failed") end
print("test_dungeon: all checks passed")
