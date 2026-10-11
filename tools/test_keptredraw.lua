-- One pricing pass per queue redraw.
--
-- A hitch each time a craft finished (2026-10-11): the Queue tab and the
-- craft pane between them built the entry costs and the shopping list three
-- or four times in one go. Within Queue:Keeping each is built once, built
-- again when the queue, the bags, a setting or a price moves, and never
-- kept outside it. Drives the real Queue.lua.

local ns = {}
ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
ns.RegisterCommand = function() end
ns.RegisterEvent = function() end
ns.Print, ns.PrintRaw, ns.Debug, ns.Warn = function() end, function() end, function() end, function() end
ns.Config = { changes = 0, Get = function() return nil end }
ns.Inventory = { changes = 0 }
ns.Prices = { changes = 0 }

assert(loadfile(lfs_cwd .. "/Logic/Queue.lua"))("Blackthornes_TS", ns)
local Queue = ns.Queue

local builds = { costs = 0, shopping = 0 }
function Queue:BuildEntryCosts() builds.costs = builds.costs + 1; return { n = builds.costs } end
function Queue:BuildShoppingList() builds.shopping = builds.shopping + 1; return { n = builds.shopping } end

local passed, failed = 0, 0
local function check(label, ok)
    if ok then passed = passed + 1; print("  ok  " .. label)
    else failed = failed + 1; print("  FAIL  " .. label) end
end

-- Outside a redraw every ask builds afresh.
Queue:GetShoppingList(); Queue:GetShoppingList()
check("outside a redraw nothing is kept", builds.shopping == 2)

builds.costs, builds.shopping = 0, 0
local same
Queue:Keeping(function()
    local a = Queue:GetShoppingList()
    local b = Queue:GetShoppingList()
    Queue:GetEntryCosts(); Queue:GetEntryCosts(); Queue:GetEntryCosts()
    same = a == b
end)
check("a redraw builds the shopping list once", builds.shopping == 1 and same)
check("and the entry costs once", builds.costs == 1)

Queue:GetShoppingList()
check("forgotten once the redraw is over", builds.shopping == 2)

builds.shopping = 0
Queue:Keeping(function()
    Queue:GetShoppingList()
    Queue.version = (Queue.version or 0) + 1
    Queue:GetShoppingList()
    ns.Inventory.changes = ns.Inventory.changes + 1
    Queue:GetShoppingList()
    ns.Config.changes = ns.Config.changes + 1
    Queue:GetShoppingList()
    ns.Prices.changes = ns.Prices.changes + 1
    Queue:GetShoppingList()
    Queue:GetShoppingList()
end)
check("the queue, bags, a setting or a price moving builds again", builds.shopping == 5)

-- Nested redraws share it; results and errors pass through.
builds.shopping = 0
local x, y = Queue:Keeping(function()
    Queue:GetShoppingList()
    Queue:Keeping(function() Queue:GetShoppingList() end)
    Queue:GetShoppingList()
    return 1, 2
end)
check("a redraw inside a redraw shares the list", builds.shopping == 1)
check("results are passed on", x == 1 and y == 2)
local ok = pcall(Queue.Keeping, Queue, function() error("boom") end)
check("errors are passed on", not ok)
builds.shopping = 0
Queue:GetShoppingList(); Queue:GetShoppingList()
check("and nothing stays kept after one", builds.shopping == 2)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then error(("%d kept redraw check(s) failed"):format(failed)) end
