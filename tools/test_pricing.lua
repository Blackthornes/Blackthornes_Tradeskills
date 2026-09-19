-- Minimal stubs so Data/Prices.lua can be loaded outside WoW.
local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.Util = { Clamp = function(v,l,h) return math.max(l, math.min(h,v)) end,
            Count = function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end,
            FormatMoney = function(c) return tostring(c) end,
            FormatAge = function() return "" end,
            HasFunction = function() return false end,
            GetItemLabel = function(i) return "item"..tostring(i) end }
ns.NewModule = function(_) return {} end
ns.RegisterCommand = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Config = { Get = function(_, k) if k == "undercutCopper" then return 1 end return 0 end }

local chunk = assert(loadfile(lfs_cwd .. "/Data/Prices.lua"))
local Prices
do
  local realNew = ns.NewModule
  ns.NewModule = function(name) local m = realNew(name); ns[name] = m; Prices = m; return m end
  chunk("Blackthornes_TS", ns)
end

local function run(label, listings)
  local market, min, qty, rivalMin, ownMin = Prices:Summarise(listings)
  local post = rivalMin and math.max(1, rivalMin - 1) or nil
  print(string.format("%-34s min=%-6s own=%-6s rival=%-6s -> post at %s",
    label, tostring(min), tostring(ownMin), tostring(rivalMin), tostring(post)))
end

print("")
run("rival far BELOW your listing", {
  {unitPrice=10, quantity=5, isOwn=false},
  {unitPrice=500, quantity=5, isOwn=true},
})
run("rival ABOVE your listing", {
  {unitPrice=100, quantity=5, isOwn=true},
  {unitPrice=500, quantity=5, isOwn=false},
})
run("only your own listing", {
  {unitPrice=100, quantity=5, isOwn=true},
})
run("many rivals, cheapest wins", {
  {unitPrice=7,  quantity=1, isOwn=false},
  {unitPrice=9,  quantity=3, isOwn=false},
  {unitPrice=50, quantity=9, isOwn=true},
})
run("you are cheapest, rival above", {
  {unitPrice=20, quantity=2, isOwn=true},
  {unitPrice=80, quantity=4, isOwn=false},
})
print("")
