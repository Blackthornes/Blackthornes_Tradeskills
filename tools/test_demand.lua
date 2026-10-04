-- Logic/Demand.lua outside WoW: how well an item sells.
--
--   1. Your own listings decide once three have ended; until then the market's
--      movement between scans does.
--   2. Cancelled listings never count against an item.
--   3. With neither, there is no reading, never a guess.
--   4. The queue warning says so once per item, and only for low demand.

local ns = {}
ns.COLORS = setmetatable({}, { __index = function() return "ffffffff" end })
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local warnings = {}
ns.Warn = function(text) warnings[#warnings + 1] = text end

local entries = {}
local items = {}
ns.Mail = {
  GetLedger = function() return { entries = entries } end,
  GetItems = function() return items end,
  LedgerCutoff = function() return nil end,
}

local prices = {}
local liquidity = {}
ns.Prices = {
  Get = function(_, itemID) return prices[itemID] end,
  GetLiquidity = function(_, itemID) return liquidity[itemID] end,
}

local chunk = assert(loadfile(lfs_cwd .. "/Logic/Demand.lua"))
chunk("Blackthornes_TS", ns)

local Demand = ns.Demand
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

local function Ledger(newItems)
  items = newItems
  entries[#entries + 1] = { t = #entries + 1 }
end

local function History(n)
  local h = {}
  for i = 1, n do h[i] = { t = i, q = 10 } end
  return h
end

print("\nyour own sales")
Ledger({ { itemID = 1, sold = 7, expired = 2, cancelled = 5 } })
local r = Demand:Get(1)
check("seven of nine sold is high", r and r.level, "high")
check("from your own sales", r and r.source, "yours")
check("cancelled ones are left out", r and r.ended, 9)
check("the tooltip says why", Demand:TooltipText(r), "High (you sold 7 of 9 listed)")

Ledger({ { itemID = 1, sold = 1, expired = 7 } })
r = Demand:Get(1)
check("one of eight is low", r and r.level, "low")
check("coloured as a loss", Demand:Color(r), "loss")

Ledger({ { itemID = 1, sold = 2, expired = 3 } })
check("two of five is some", Demand:Get(1).level, "some")

print("\nthe market, until three of yours have ended")
Ledger({ { itemID = 2, sold = 1, expired = 1 } })
prices[2] = { history = History(4) }
liquidity[2] = 0.2
r = Demand:Get(2)
check("two ended is not enough of your own", r and r.source, "market")
check("a fifth of the stock moving is high", r and r.level, "high")
check("the tooltip says why", Demand:TooltipText(r), "High (20% of its stock sells between scans)")

liquidity[2] = 0.01
check("barely moving is low", Demand:Get(2).level, "low")

prices[2] = { history = History(2) }
check("two scans are not enough", Demand:Get(2), nil)

check("never seen has no reading", Demand:Get(99), nil)
check("and no label", Demand:Label(nil), nil)
check("sorts below anything known", Demand:Rank(nil) < Demand:Rank({ level = "low", rate = 0 }), true)

print("\nthe queue warning")
Ledger({ { itemID = 3, sold = 0, expired = 6 }, { itemID = 4, sold = 6, expired = 0 } })
check("a craft that rarely sells is warned about", Demand:WarnIfLow(3, "Minor Mana Potion"), true)
check("naming it", warnings[1]:find("Minor Mana Potion rarely sells", 1, true) ~= nil, true)
check("once a session", Demand:WarnIfLow(3, "Minor Mana Potion"), false)
check("a craft that sells is not", Demand:WarnIfLow(4, "Linen Bandage"), false)
check("nor one with no reading", Demand:WarnIfLow(99, "Something"), false)

print("")
if failures > 0 then
  error(string.format("%d demand check(s) failed", failures))
end
print("  all demand checks passed")
print("")
