-- Every character's bank in one list (Logic/Banks.lua).
--
-- The list is built from counts Inventory already saved, so what matters is
-- that it adds them up right, keeps each character's share apart, prices grey
-- items at the vendor only, survives an item name it cannot read, and never
-- writes anything back into the saved data.

local saved = { C_Item = C_Item, Enum = Enum }

local ns = {}
ns.NewModule = function(name) local m = {}; ns[name] = m; return m end
local commands = {}
ns.RegisterCommand = function(name, _, fn) commands[name] = fn end
ns.Print = function() end

-- Pretend items: 1 Silk Cloth (white), 2 Broken Fang (grey), 3 an item the
-- client hands back as a secret name, 4 an item the client has not loaded.
local ITEMS = {
    [1] = { name = "Silk Cloth", quality = 1, sell = 38 },
    [2] = { name = "Broken Fang", quality = 0, sell = 5 },
    [3] = { secret = true, quality = 1, sell = 10 },
}

local secretName = setmetatable({}, {
    __concat = function() error("attempt to concatenate a secret string value") end,
    __tostring = function() error("secret") end,
    __index = function() error("secret") end,
})

C_Item = {
    GetItemInfo = function(itemID)
        local item = ITEMS[itemID]
        if not item then return nil end
        local name = item.secret and secretName or item.name
        return name, nil, item.quality, nil, nil, nil, nil, nil, nil, nil, item.sell
    end,
}
Enum = nil

ns.Util = {
    HasFunction = function(path) return path == "C_Item.GetItemInfo" end,
    GetVendorSellPrice = function(itemID) return ITEMS[itemID] and ITEMS[itemID].sell or nil end,
}

-- Auction prices: silk is worth more at auction than to a vendor, and the
-- grey fang has an auction price the addon must ignore.
local AUCTION = { [1] = 120, [2] = 999 }
ns.Prices = { GetValue = function(_, itemID) return AUCTION[itemID] end }

ns.Disenchant = { KnownName = function(_, itemID) if itemID == 4 then return "Saved Name" end end }

ns.Config = { GetCharacterKey = function() return "Player-main" end }

ns.db = {
    characters = {
        ["Player-main"] = {
            name = "Main", bank = { [1] = 20, [2] = 3 }, bankAt = 1000,
            inventory = { [1] = 99 },   -- stale: the live bags below win
        },
        ["Player-alt"] = {
            name = "Alt", bank = { [1] = 40, [3] = 1, [4] = 2 }, bankAt = 2000,
            inventory = { [1] = 5 },
        },
        ["Player-new"] = { name = "New", recipes = {}, inventory = { [2] = 1 } },
    },
}

ns.Inventory = { GetBagCounts = function() return { [1] = 7 } end }

ns.Recipes = {
    GetCharacters = function()
        return {
            { key = "Player-main", name = "Main", isCurrent = true, bankAt = 1000 },
            { key = "Player-alt", name = "Alt", isCurrent = false, bankAt = 2000 },
            { key = "Player-new", name = "New", isCurrent = false },
        }
    end,
}

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = Copy(v) end
    return out
end

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local before = Copy(ns.db)

assert(loadfile(lfs_cwd .. "/Logic/Banks.lua"))("Blackthornes_TS", ns)
local Banks = ns.Banks

local function Find(list, itemID)
    for _, entry in ipairs(list) do
        if entry.itemID == itemID then return entry end
    end
end

local function Holder(entry, key)
    for _, holder in ipairs(entry.holders) do
        if holder.key == key then return holder end
    end
end

-- The client answers type() honestly for a secret ("string"), so the fake
-- does too while the list is built; only using the value raises.
local realType = type
type = function(v) if rawequal(v, secretName) then return "string" end return realType(v) end
local ok, collected = pcall(Banks.Collect, Banks)
type = realType
assert(ok, "a secret item name raised: " .. tostring(collected))

-- Banks only: silk from two banks, each character's share kept apart.
local list = collected
local silk = Find(list, 1)
assert(silk.total == 60 and silk.bank == 60 and silk.bags == 0, "silk counted from both banks")
assert(#silk.holders == 2, "two holders")
assert(silk.holders[1].key == "Player-alt", "the bigger holder first")
assert(Holder(silk, "Player-main").bank == 20)
assert(Find(list, 2).total == 3, "a character with no bank adds nothing")

-- Worth: the better of auction and vendor; grey at vendor only.
assert(silk.unit == 120 and silk.worth == 7200, "silk at its auction price")
local fang = Find(list, 2)
assert(fang.unit == 5, "grey item priced at vendor only, got " .. tostring(fang.unit))

-- A secret name costs the name, not the list.
local secret = Find(list, 3)
assert(secret and secret.name == "item 3", "secret name falls back to the ID")
assert(Find(list, 4).name == "Saved Name", "an unloaded item uses the saved name")

-- Bags too: the current character's live bags, everyone else's snapshot.
list = Banks:Collect({ bags = true })
silk = Find(list, 1)
assert(silk.total == 72, "60 in banks + 7 live bags + 5 on the alt, got " .. silk.total)
assert(Holder(silk, "Player-main").bags == 7, "live bags beat the stale snapshot")
assert(Holder(silk, "Player-alt").bags == 5)
assert(Find(list, 2).total == 4, "bags from a character whose bank was never read")

-- One character, and search.
list = Banks:Collect({ character = "Player-alt" })
assert(Find(list, 1).total == 40 and not Find(list, 2), "only the alt's bank")

list = Banks:Collect({ search = "SILK" })
assert(#list == 1 and list[1].itemID == 1, "search ignores case")

-- Sorting.
list = Banks:Sort(Banks:Collect(), "count")
assert(list[1].itemID == 1, "most held first")
list = Banks:Sort(Banks:Collect(), "name")
assert(list[1].name == "Broken Fang", "by name")
list = Banks:Sort(Banks:Collect(), "worth")
assert(list[1].itemID == 1, "most valuable first")

-- Overview: a row per character, the unread bank marked by its missing time.
local overview = Banks:Overview()
assert(#overview == 3)
assert(overview[1].key == "Player-main" and overview[1].count == 23)
assert(overview[1].worth == 20 * 120 + 3 * 5, "main's bank worth")
assert(overview[3].bankAt == nil and overview[3].count == 0, "never-opened bank")

-- Nothing written back into the saved data.
assert(Same(before, ns.db), "saved data changed")

-- The command exists.
assert(commands.bank, "/bts bank registered")

C_Item, Enum = saved.C_Item, saved.Enum
