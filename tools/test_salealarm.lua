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
-- Another suite may have left one behind. Without it the picked sound
-- cannot play, so the raid warning does, as on a game without the call.
PlaySoundFile = nil

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
settings.saleSound = "raid"

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

print("\npicking the sound")
SOUNDKIT = { RAID_WARNING = 8959 }
local files = {}
local fileAnswer = true
PlaySoundFile = function(file, channel)
  files[#files + 1] = { file = file, channel = channel }
  return fileAnswer
end
PlaySound = function(kit, channel)
  sounds[#sounds + 1] = { kit = kit, channel = channel }
  return true, #sounds
end

settings.saleSound = nil
check("nothing picked: the cash register", SaleAlarm:Sound(), "register")
local before = #sounds
SaleAlarm:Play()
check("the register file plays", files[#files] and files[#files].file,
  "Interface\\AddOns\\Blackthornes_TS\\Media\\Sounds\\sale-register.ogg")
check("on the master channel", files[#files] and files[#files].channel, "Master")
check("and no raid warning on top", #sounds, before)

settings.saleSound = "coins"
SaleAlarm:Play()
check("coins: the game's loot coins by file ID", files[#files].file, 567413)

settings.saleSound = "raid"
local fileCount = #files
SaleAlarm:Play()
check("raid: no file", #files, fileCount)
check("raid: the raid warning", sounds[#sounds].kit, 8959)

settings.saleSound = "something old"
check("an unknown saved value is the register", SaleAlarm:Sound(), "register")

settings.saleSound = "raid"
SaleAlarm:Play("coins")
check("the play button can ask for one that is not picked", files[#files].file, 567413)

settings.saleSound = "register"
fileAnswer = false
before = #sounds
SaleAlarm:Play()
check("a file the game refuses (before a restart): the raid warning", #sounds, before + 1)
check("and that is the raid warning", sounds[#sounds].kit, 8959)
PlaySoundFile = function() error("no such file") end
SaleAlarm:Play()
check("a file call that throws: the raid warning too", #sounds, before + 2)
PlaySoundFile = nil
settings.saleSound = nil

print("\nthe Sales tab and the chat filter")

ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
SaleAlarm:InvalidatePattern()
local heard = {}
ns.Mail = { NoteHeardSale = function(_, name) heard[#heard + 1] = name end }
local filters = {}
ChatFrame_AddMessageEventFilter = function(event, fn) filters[event] = fn end
ns.accepts.CHAT_MSG_SYSTEM = true
SaleAlarm:OnEnable()
check("the filter is installed", type(filters.CHAT_MSG_SYSTEM), "function")
check("and /bts salealarm can say so", SaleAlarm.filtering, true)

SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Heavy Silk Bandage.")
check("a sale goes to the Sales tab", heard[#heard], "Heavy Silk Bandage")
SaleAlarm:AUCTION_HOUSE_SHOW_NOTIFICATION("x", 4)
check("the notice does not log it twice", #heard, 1)

local filter = filters.CHAT_MSG_SYSTEM
local soldLine = "A buyer has been found for your auction of Heavy Silk Bandage."
settings.hideSaleChat = nil
check("left in chat by default", filter(nil, "CHAT_MSG_SYSTEM", soldLine), false)
settings.hideSaleChat = true
check("hidden when the player asks", filter(nil, "CHAT_MSG_SYSTEM", soldLine), true)
check("other system lines stay", filter(nil, "CHAT_MSG_SYSTEM", "You are now AFK."), false)
settings.hideSaleChat = nil

-- Seen in game: the line in chat came from the notice, with the item's name
-- as its text, and no CHAT_MSG_SYSTEM at all.
print("\nthe notice route, as Forever sends it")
Enum = { AuctionHouseNotification = { AuctionSold = 4 } }
heard = {}
later()
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION("x", 4, "Woolen Bag")
check("the notice's sale goes to the Sales tab", heard[1], "Woolen Bag")
SaleAlarm:CHAT_MSG_SYSTEM("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Woolen Bag.")
check("the same sale by chat a moment later is not logged twice", #heard, 1)
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION("x", 4, "Woolen Bag")
check("a second notice for the same item is a second sale", #heard, 2)
later()
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION("x", 4, "|cff1eff00|Hitem:4240::|h[Woolen Bag]|h|r")
check("a link is read as its name", heard[3], "Woolen Bag")
SaleAlarm:AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION("x", 3, "Woolen Bag")
check("an outbid notice is not a sale", #heard, 3)

print("\nhiding the line the notice prints")
local printed = {}
ChatFrame1 = { AddMessage = function(_, text) printed[#printed + 1] = text end }
NUM_CHAT_WINDOWS = 1
settings.hideSaleChat = nil
check("nothing is wrapped while hiding is off", SaleAlarm:InstallChatHider(), false)
settings.hideSaleChat = true
check("wrapped once hiding is on", SaleAlarm:InstallChatHider(), true)
ChatFrame1:AddMessage("A buyer has been found for your auction of Woolen Bag.", 1, 1, 0)
ChatFrame1:AddMessage("|cffffff00A buyer has been found for your auction of Woolen Bag.|r")
check("the sold line, coloured or not, is kept out", #printed, 0)
ChatFrame1:AddMessage("[2. Trade] anyone selling bags?")
check("everything else still prints", #printed, 1)
settings.hideSaleChat = nil
ChatFrame1:AddMessage("A buyer has been found for your auction of Woolen Bag.")
check("turned off, the line prints again", #printed, 2)
ChatFrame1, NUM_CHAT_WINDOWS = nil, nil
ChatFrame_AddMessageEventFilter, ns.Mail = nil, nil

print("")
if failures > 0 then
  error(string.format("%d sale alarm check(s) failed", failures))
end
print(string.format("  all sale alarm checks passed"))
print("")
