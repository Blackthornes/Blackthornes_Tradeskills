-- Logic/Butler.lua's Lists outside WoW.
--
-- Butler's bank alt can take everything on one of the player's shopping
-- lists (2026-10-14). What must hold:
--   1. Each list the player made comes back by name, in order, its items
--      as [itemID] = how many are wanted, with its id (Butler keeps its
--      own rules for a list by it).
--   2. A broken entry is skipped, never raised on, and nothing is written.
--   3. Fresh tables each time, so Butler may keep or change them.
--   4. Without the lists module, or when it raises, the answer is nil.

local ns = {}
ns.NewModule = function(name) local m = {} ns[name] = m return m end

local saved = {
  { name = "Cloth", id = 4, items = { { id = 2589, want = 40 }, { id = 4306 }, { id = "bad" }, "junk" } },
  { name = "Herbs", items = { { id = 765, want = 20 } } },
}
ns.ShoppingLists = { version = 7, Readable = function()
  local out = {}
  for index, list in ipairs(saved) do out[#out + 1] = { index = index, list = list } end
  return out
end }

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
local lists, version = Butler:Lists()
check("two lists", lists and #lists, 2)
check("by name, in order", lists and lists[1].name .. "," .. lists[2].name, "Cloth,Herbs")
check("an item with how many are wanted", lists[1].items[2589], 40)
check("an item with no number wants 0", lists[1].items[4306], 0)
check("the version comes along", version, 7)
check("each list's id comes along", lists[1].id, 4)
check("a list with no id has none", lists[2].id, nil)

-- 2.
local count = 0
for _ in pairs(lists[1].items) do count = count + 1 end
check("broken items are skipped", count, 2)
check("nothing is written to the save", #saved[1].items, 4)

-- 3.
lists[1].items[2589] = 1
check("a fresh table each time", Butler:Lists()[1].items[2589], 40)

-- 4.
ns.ShoppingLists.Readable = function() error("broken") end
check("a raising module gives nil", Butler:Lists(), nil)
ns.ShoppingLists = nil
check("no lists module gives nil", Butler:Lists(), nil)

if failures > 0 then
  error(("%d check(s) failed"):format(failures))
end
print("butlerlists: all checks passed")
