-- Blackthornes Tradeskills -- Logic/KeepHere.lua
-- Keep a number of an item on one character, so the Sell list offers only
-- what is past it (a player asked, the owner said build it, 2026-10-18).
-- The Sell list's x hides an item on every character; this is for one.
--
-- Butler has the same choice ("Keep on This Character", its
-- Logic/KeepHere.lua). Where both have a number, the bigger one wins, in
-- both addons: SisterKeeps reads Butler's, and Butler reads this one,
-- inside a pcall, read only:
--
--   _G.BlackthornesTS.KeepHere:Count(itemID)   -- how many to keep here, or nil
--   _G.BlackthornesTS.KeepHere.IsAll(count)    -- true for Keep All
--
-- Keep both stable; if one changes, change Butler's Logic/KeepHere.lua too.
--
-- Saved account wide, by character GUID, never renamed:
--   keepOnCharacter = { [GUID] = { [itemID] = count } }
-- A character whose GUID the client won't give (a dungeon, before the key
-- is known) reads nothing and writes nothing.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local KeepHere = ns.NewModule("KeepHere")

-- The most a box takes. Keep All saves this, so every one stays.
KeepHere.MOST = 9999

-- Moves whenever a number is set, so lists that show them know to redraw.
KeepHere.version = 0

--- True when the number means every one (Keep All).
function KeepHere.IsAll(count)
    return type(count) == "number" and count >= KeepHere.MOST
end

--- The number as a player reads it: "All" for Keep All.
function KeepHere.Shown(count)
    if KeepHere.IsAll(count) then return L["All"] end
    return tostring(count or 0)
end

local function Clean(count)
    count = math.floor(tonumber(count) or 0)
    return math.max(0, math.min(KeepHere.MOST, count))
end

--- The character playing's GUID, or nil when it isn't known.
function KeepHere.PlayerKey()
    local key = ns.Config and ns.Config.GetCharacterKey and ns.Config:GetCharacterKey()
    if type(key) == "string" and key:find("^Player%-") then return key end
    return nil
end

local function List(make)
    local key = KeepHere.PlayerKey()
    if not key or not ns.db then return nil end
    local all = ns.db.keepOnCharacter
    if type(all) ~= "table" then
        if not make then return nil end
        all = {}
        ns.db.keepOnCharacter = all
    end
    local mine = all[key]
    if type(mine) ~= "table" then
        if not make then return nil end
        mine = {}
        all[key] = mine
    end
    return mine
end

--- How many of an item the character playing keeps, or nil for none.
function KeepHere:Count(itemID)
    itemID = tonumber(itemID)
    local mine = itemID and List()
    local count = mine and Clean(mine[itemID]) or 0
    if count > 0 then return count end
    return nil
end

--- Keep `count` of an item on the character playing. 0 or nil takes it off
--- the list. True, or false and why.
function KeepHere:Set(itemID, count)
    itemID = tonumber(itemID)
    if not itemID then return false end
    if not self.PlayerKey() then
        return false, L["Tradeskills can't tell which character you're on right now. Try again outside the dungeon."]
    end
    count = Clean(count)
    local mine = List(count > 0)
    if mine then mine[itemID] = count > 0 and count or nil end
    self.version = self.version + 1
    if ns.SisterKeeps then ns.SisterKeeps:Forget() end
    if ns.Posting then ns.Posting.changes = (ns.Posting.changes or 0) + 1 end
    if ns.PostPanel and ns.PostPanel.Refresh then ns.PostPanel:Refresh() end
    if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
    return true
end

--- The character playing's list: { itemID, count, name }, A to Z.
function KeepHere:Items()
    local list = {}
    for itemID, count in pairs(List() or {}) do
        count = Clean(count)
        if type(itemID) == "number" and count > 0 then
            local name
            if C_Item and type(C_Item.GetItemInfo) == "function" then
                local ok, itemName = pcall(C_Item.GetItemInfo, itemID)
                if ok and type(itemName) == "string" and itemName ~= "" then name = itemName end
            end
            list[#list + 1] = { itemID = itemID, count = count, name = name or ("item " .. itemID) }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.itemID < b.itemID
    end)
    return list
end
