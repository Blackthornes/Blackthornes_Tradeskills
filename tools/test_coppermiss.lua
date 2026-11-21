-- A gear listing with copper in its price that does not show up in your
-- auctions must not switch the rest of the session to whole silver.
--
-- The owner's report (2026-11-19): Robes of Arcana listed at 1g 81s 00c
-- while the cheapest was 1g 80s 09c. One missed listing (often only a slow
-- or misread auctions list) had turned on the whole silver fallback, and
-- every gear price after it rounded up to a silver. Forever takes copper on
-- gear (tried in game 2026-11-16), so a miss never changes the price step.

local ns = {}
ns.COLORS = setmetatable({}, {__index = function() return "ffffffff" end})
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
CreateFrame = function()
    local frame = {}
    for _, name in ipairs({ "SetScript", "Show", "Hide", "SetPoint", "SetSize" }) do
        frame[name] = function() end
    end
    return frame
end
GetTime = function() return os.clock() end
time = time or os.time

assert(loadfile(lfs_cwd .. "/Core/Util.lua"))("Blackthornes_TS", ns)
ns.Config = { Get = function() return nil end, GetPriceTable = function() return {} end }
ns.Scanner = { IsCommodity = function() return false end }
ns.Cost = { FindRecipeForItem = function() return nil end }
ns.Cost.FindAnyRecipeForItem = ns.Cost.FindRecipeForItem
assert(loadfile(lfs_cwd .. "/Logic/Posting.lua"))("Blackthornes_TS", ns)

local Util, Posting = ns.Util, ns.Posting
local failures = 0
local function check(label, got, expected)
    local ok = got == expected
    if not ok then failures = failures + 1 end
    print(string.format("  %-52s %-8s %s", label, tostring(got),
        ok and "ok" or ("EXPECTED " .. tostring(expected))))
end

print("")
print("a gear listing at 1g 80s 09c that did not show up")
Util.wholeSilverOnly = false
local switched = Posting:FallBackToWholeSilver({ itemID = 14106, unitPrice = 18009, isCommodity = false })
check("does not switch to whole silver", switched, false)
check("whole silver stays off", Util.wholeSilverOnly, false)
check("the next price keeps its copper", Util.ItemAuctionPriceUp(18009), 18009)
check("a copper price is still one the game takes", Util.IsItemAuctionPrice(18009), true)

print("")
if failures > 0 then error(failures .. " copper miss check(s) failed") end
print("all copper miss checks passed")
