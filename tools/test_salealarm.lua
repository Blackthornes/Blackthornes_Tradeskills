-- Logic/SaleAlarm.lua outside WoW.
--
-- Whether this version of the game sends the sold chat line, the auction house
-- notice, or both, can only be seen in game: /bts salealarm counts each one.
-- What IS testable is what happens once either arrives:
--
--   1. Only YOUR sale sounds the alarm. Every other system line, and every
--      other auction notice (outbid, expired, won), must stay silent -- an
--      alarm that goes off for the wrong thing gets turned off.
--   2. The line is matched from the game's own text, so a game running in
--      another language still works, and a game without that text is silent
--      rather than guessing.
--   3. Both routes reporting one sale, or several sales at once, is ONE alarm.
--   4. The setting turns it off, and the sale is still counted when it is off.

local clock = 100
GetTime = function() return clock end
time = function() return 5000 end

local sounds = {}
PlaySound = function(kit, channel)
  sounds[#sounds + 1] = { kit = kit, channel = channel }
  return true, #sounds
end

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end
-- The game refuses an event it does not know; a case below takes one away.
ns.RegisterEvent = function(_, event, fn)
  assert(type(fn) == "function", "no handler for " .. event)
  return ns.accepts[event] == true
end
ns.RegisterCommand = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn =
  function() end, function() end, function() end, function() end
ns.accepts = {
  CHAT_MSG_SYSTEM = true,
  AUCTION_HOUSE_SHOW_NOTIFICATION = true,
  AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION = true,
}

local settings = {}
ns.Config = { Get = function(_, key) return settings[key] end }

ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
Enum = { AuctionHouseNotification = {
  BidPlaced = 0, AuctionRemoved = 1, AuctionWon = 2,
  AuctionOutbid = 3, AuctionSold = 4, AuctionExpired = 5,
} }
SOUNDKIT = { RAID_WARNING = 8959 }

local chunk = assert(loadfile(lfs_cwd .. "/Logic/SaleAlarm.lua"))
chunk("Blackthornes_TS", ns)

local SaleAlarm = ns.SaleAlarm
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

local function later() clock = clock + 60 end

SaleAlarm:OnEnable()

print("\nlistening")
check("chat line route is on", SaleAlarm.listening.chat, true)
check("notice route is on", SaleAlarm.listening.notice, true)

-- A game that knows neither notice event still listens for the chat line.
ns.accepts.AUCTION_HOUSE_SHOW_NOTIFICATION = nil
ns.accepts.AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION = nil
SaleAlarm:OnEnable()
check("no notice events: notice route is off", SaleAlarm.listening.notice, false)
check("no notice events: chat line route still on", SaleAlarm.listening.chat, true)

print("\nthe sold chat line")
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Linen Bag.")
check("one alarm", #sounds, 1)
check("played the raid warning", sounds[1] and sounds[1].kit, 8959)
check("on the master channel", sounds[1] and sounds[1].channel, "Master")
check("item name read from the line", SaleAlarm.lastSale.item, "Linen Bag")
check("counted as the chat line", SaleAlarm.heard.chat, 1)

later()
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "You have been outbid on Linen Bag.")
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "Xyz has come online.")
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "Someone said: A buyer has been found for your auction of Linen Bag. lol")
check("other system lines stay silent", #sounds, 1)

-- An item name with pattern characters in it must still match, and must not
-- break the pattern for the next one.
later()
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Potion (50%) [Minor].")
check("item name with pattern characters", SaleAlarm.lastSale.item, "Potion (50%) [Minor]")
check("and it sounded", #sounds, 2)

print("\nthe auction house notice")
later()
SaleAlarm:AUCTION_HOUSE_SHOW_NOTIFICATION("AUCTION_HOUSE_SHOW_NOTIFICATION", 3)
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 5, "Linen Bag")
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 2, "Linen Bag")
check("outbid, expired and won stay silent", #sounds, 2)

SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Copper Bar")
check("sold notice sounds", #sounds, 3)
check("item name from the notice", SaleAlarm.lastSale.item, "Copper Bar")
check("counted as the notice", SaleAlarm.heard.notice, 1)

print("\none sale, two routes")
later()
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION(
  "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", 4, "Silk Cloth")
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Silk Cloth.")
check("both routes, one alarm", #sounds, 4)
check("both still counted", SaleAlarm.heard.chat + SaleAlarm.heard.notice, 5)

clock = clock + 1
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Wool Cloth.")
check("a second sale a moment later, still one", #sounds, 4)

clock = clock + 2
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Wool Cloth.")
check("after the quiet spell, a new alarm", #sounds, 5)

print("\nthe setting")
later()
settings.saleAlarm = false
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Linen Bag.")
check("off: no sound", #sounds, 5)
check("off: the sale is still counted", SaleAlarm.heard.chat, 6)
settings.saleAlarm = true
later()
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM",
  "A buyer has been found for your auction of Linen Bag.")
check("back on: sounds again", #sounds, 6)
settings.saleAlarm = nil
check("never set counts as on", SaleAlarm:IsOn(), true)

print("\nanother language")
ERR_AUCTION_SOLD_S = "Un acheteur a \195\169t\195\169 trouv\195\169 pour votre vente aux ench\195\168res de %s."
SaleAlarm:InvalidatePattern()
check("French line matches", SaleAlarm:MatchSoldLine(
  "Un acheteur a \195\169t\195\169 trouv\195\169 pour votre vente aux ench\195\168res de Sac en lin."),
  "Sac en lin")
check("English line does not", SaleAlarm:MatchSoldLine(
  "A buyer has been found for your auction of Linen Bag."), nil)

print("\nwhat the game does not have")
ERR_AUCTION_SOLD_S = nil
SaleAlarm:InvalidatePattern()
check("no sold text: nothing matches", SaleAlarm:MatchSoldLine("anything at all"), nil)

Enum = nil
check("no enum: no notice counts as sold", SaleAlarm:IsSoldNotice(4), false)

SOUNDKIT = nil
later()
SaleAlarm:Play()
check("no SOUNDKIT table: plays the raid warning by number", sounds[#sounds].kit, 8959)

PlaySound = function() end
check("a game that returns nothing is not a refusal", SaleAlarm:Play(), "unknown")
PlaySound = function() error("no such sound") end
check("a game that throws is a refusal", SaleAlarm:Play(), false)

print("")
if failures > 0 then
  error(string.format("%d sale alarm check(s) failed", failures))
end
print(string.format("  all sale alarm checks passed"))
print("")
