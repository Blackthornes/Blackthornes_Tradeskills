-- Blackthornes Tradeskills -- Logic/Legacy.lua
-- The character's Legacy perks, read only.
--
-- Forever's Legacy is a trait config (the spell "Legacy System - Create
-- Trait Config"), the same C_Traits system class talents use. Points are
-- spent by the player in the game's own window; this file only reads what
-- is spent. It never buys a rank, never commits a config and never
-- suggests a build (the owner, 2026-10-22: "we just read what they have
-- set").
--
-- Used for one thing so far: Master Chef, which gives extra results when
-- cooking, so a cooking recipe's yield on the Profit tab follows it
-- (Cost:GetCraftCost). Bartering needs nothing here: vendor prices are read
-- off the real merchant window, which already has the discount.
--
-- Every client call is inside a pcall. When nothing can be read, every
-- answer is the plain one (no bonus), so the addon works as before.
-- `/bts probe` prints what was found ("legacy" lines).

local _, ns = ...

local Legacy = ns.NewModule("Legacy")

-- Node IDs seen for the Legacy trees on the beta. Not confirmed: they are
-- only used to tell the Legacy config from other trait configs.
Legacy.NODE_FIRST = 110284
Legacy.NODE_LAST = 110319

-- Currencies in the client's tables: Legacy Track renown and the reset
-- charges.
Legacy.CURRENCIES = { 3485, 3499 }

-- Master Chef: "cooking gives an extra result", up to 50% at its last rank
-- (beta values). Found by its English name; MASTER_CHEF_NODE can pin the
-- node once a probe shows its ID, for clients in other languages.
Legacy.MASTER_CHEF_NAME = "master chef"
Legacy.MASTER_CHEF_NODE = nil
Legacy.MASTER_CHEF_MOST = 0.5

-- Systems and trees tried when looking for the config. The search runs a
-- slice a frame, once a session (and again after a trait event).
Legacy.SYSTEMS_LAST = 100
Legacy.TREES_LAST = 1500
Legacy.SLICE = 150

local function Call(path, ...)
    local fn = _G
    for part in path:gmatch("[^.]+") do
        if type(fn) ~= "table" then return nil end
        fn = fn[part]
    end
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

local function Number(value)
    local ok, result = pcall(function() return type(value) == "number" and value or nil end)
    return ok and result or nil
end

--------------------------------------------------------------------------------
-- Finding the config
--------------------------------------------------------------------------------

--- The class talent config, never mistaken for Legacy's.
local function ClassConfig()
    return Number(Call("C_ClassTalents.GetActiveConfigID"))
end

--- The node IDs of a config's trees, or nil.
function Legacy:ConfigNodes(configID)
    local info = Call("C_Traits.GetConfigInfo", configID)
    if type(info) ~= "table" or type(info.treeIDs) ~= "table" then return nil end
    local nodes, trees = {}, {}
    for _, treeID in ipairs(info.treeIDs) do
        trees[#trees + 1] = treeID
        local ids = Call("C_Traits.GetTreeNodes", treeID)
        if type(ids) == "table" then
            for _, nodeID in ipairs(ids) do nodes[#nodes + 1] = nodeID end
        end
    end
    return nodes, trees, info
end

--- True when this config is the Legacy one: its name says so, or it holds
--- a node in Legacy's range.
function Legacy:IsLegacy(configID)
    if not Number(configID) or configID == ClassConfig() then return false end
    local nodes, _, info = self:ConfigNodes(configID)
    local okName, named = pcall(function()
        return type(info.name) == "string" and info.name:lower():find("legacy", 1, true) ~= nil
    end)
    if okName and named then return true end
    for _, nodeID in ipairs(nodes or {}) do
        if Number(nodeID) and nodeID >= self.NODE_FIRST and nodeID <= self.NODE_LAST then
            return true
        end
    end
    -- No tree list: ask for one of the nodes directly.
    local node = Call("C_Traits.GetNodeInfo", configID, self.NODE_FIRST)
    local ok, found = pcall(function()
        return type(node) == "table" and node.ID == self.NODE_FIRST and (node.maxRanks or 0) > 0
    end)
    return ok and found or false
end

--- The places to look, in order: every trait system ID the client names,
--- then system IDs, then tree IDs.
local function Candidates(self)
    local list = {}
    if type(Enum) == "table" then
        for enumName, values in pairs(Enum) do
            if type(enumName) == "string" and enumName:find("TraitSystem") and type(values) == "table" then
                for _, id in pairs(values) do
                    if Number(id) then list[#list + 1] = { "system", id } end
                end
            end
        end
    end
    for id = 1, self.SYSTEMS_LAST do list[#list + 1] = { "system", id } end
    for id = 1, self.TREES_LAST do list[#list + 1] = { "tree", id } end
    return list
end

local function ConfigFor(kind, id)
    if kind == "system" then
        return Number(Call("C_Traits.GetConfigIDBySystemID", id))
    end
    return Number(Call("C_Traits.GetConfigIDByTreeID", id))
end

--- Look for the config a slice a frame. `done` runs when it ends.
function Legacy:Search(done)
    if self.searching then return end
    if not (C_Traits and type(C_Traits.GetConfigInfo) == "function") then
        self.searched = true
        if done then done() end
        return
    end
    self.searching = true
    local list, index, tried = Candidates(self), 1, {}

    local function Step()
        local stop = math.min(#list, index + self.SLICE - 1)
        for i = index, stop do
            local kind, id = list[i][1], list[i][2]
            local configID = ConfigFor(kind, id)
            if configID and not tried[configID] then
                tried[configID] = true
                if self:IsLegacy(configID) then
                    self.configID, self.foundBy = configID, kind .. " " .. id
                    break
                end
            end
        end
        index = stop + 1
        if self.configID or index > #list then
            self.searching, self.searched = false, true
            self.stale = true
            if done then done() end
            return
        end
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, Step)
        else
            Step()
        end
    end
    Step()
end

--------------------------------------------------------------------------------
-- Reading the nodes
--------------------------------------------------------------------------------

local function SpellName(spellID)
    if not Number(spellID) then return nil end
    local name = Call("C_Spell.GetSpellName", spellID)
    if type(name) ~= "string" then name = Call("GetSpellInfo", spellID) end
    return type(name) == "string" and name or nil
end

--- One node: { nodeID, name, spellID, rank, maxRanks }, or nil.
function Legacy:Node(nodeID)
    local configID = self.configID
    if not configID then return nil end
    local info = Call("C_Traits.GetNodeInfo", configID, nodeID)
    if type(info) ~= "table" then return nil end
    local okSame, same = pcall(function() return info.ID == nodeID end)
    if not (okSame and same) then return nil end
    local rank = Number(info.ranksPurchased) or Number(info.currentRank) or Number(info.activeRank) or 0
    local maxRanks = Number(info.maxRanks) or 0
    local name, spellID
    local entryID = type(info.activeEntry) == "table" and info.activeEntry.entryID
        or (type(info.entryIDs) == "table" and info.entryIDs[1])
    if Number(entryID) then
        local entry = Call("C_Traits.GetEntryInfo", configID, entryID)
        local definitionID = type(entry) == "table" and Number(entry.definitionID)
        if definitionID then
            local definition = Call("C_Traits.GetDefinitionInfo", definitionID)
            if type(definition) == "table" then
                spellID = Number(definition.spellID) or Number(definition.overriddenSpellID)
                name = type(definition.overrideName) == "string" and definition.overrideName ~= ""
                    and definition.overrideName or SpellName(spellID)
            end
        end
    end
    return { nodeID = nodeID, name = name, spellID = spellID, rank = rank, maxRanks = maxRanks }
end

--- Every node of the config, in node ID order.
function Legacy:Nodes()
    local nodes = {}
    if not self.configID then return nodes end
    local ids = self:ConfigNodes(self.configID)
    if not ids or #ids == 0 then
        ids = {}
        for id = self.NODE_FIRST, self.NODE_LAST do ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return (Number(a) or 0) < (Number(b) or 0) end)
    for _, nodeID in ipairs(ids) do
        local node = self:Node(nodeID)
        if node then nodes[#nodes + 1] = node end
    end
    return nodes
end

--- Points left to spend, from the trees' currency: { { id, left, spent } }.
function Legacy:PointsLeft()
    local out = {}
    if not self.configID then return out end
    local _, trees = self:ConfigNodes(self.configID)
    for _, treeID in ipairs(trees or {}) do
        local currencies = Call("C_Traits.GetTreeCurrencyInfo", self.configID, treeID, false)
        if type(currencies) == "table" then
            for _, currency in ipairs(currencies) do
                if type(currency) == "table" then
                    out[#out + 1] = { tree = treeID, id = currency.traitCurrencyID,
                        left = Number(currency.quantity), spent = Number(currency.spent) }
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Master Chef
--------------------------------------------------------------------------------

--- Master Chef's node, found once by ID or name.
function Legacy:MasterChefNode()
    if self.masterChefNode then return self.masterChefNode end
    if self.MASTER_CHEF_NODE then
        self.masterChefNode = self.MASTER_CHEF_NODE
        return self.masterChefNode
    end
    for _, node in ipairs(self:Nodes()) do
        local ok, match = pcall(function() return node.name and node.name:lower() == self.MASTER_CHEF_NAME end)
        if ok and match then
            self.masterChefNode = node.nodeID
            return node.nodeID
        end
    end
    return nil
end

--- How many cooking results one craft gives, as a multiplier: 1 with no
--- Master Chef (or nothing read), up to 1.5 at its last rank. Kept until a
--- trait event or a new session.
function Legacy:CookingYield()
    if self.cookingYield and not self.stale then return self.cookingYield end
    local yield = 1
    if self.configID then
        local nodeID = self:MasterChefNode()
        local node = nodeID and self:Node(nodeID)
        if node and node.rank > 0 then
            local most = node.maxRanks > 0 and node.maxRanks or 5
            yield = 1 + self.MASTER_CHEF_MOST * math.min(node.rank, most) / most
        end
    end
    self.cookingYield, self.stale = yield, false
    return yield
end

--------------------------------------------------------------------------------
-- The probe
--------------------------------------------------------------------------------

local function Currency(id)
    local info = Call("C_CurrencyInfo.GetCurrencyInfo", id)
    if type(info) ~= "table" then return "none" end
    return ("%s %s/%s"):format(tostring(info.name or "?"), tostring(info.quantity),
        tostring(info.maxQuantity))
end

--- Lines for `/bts probe`, as { label, value }.
function Legacy:ProbeLines()
    local lines = {}
    local function Add(label, value) lines[#lines + 1] = { label, value } end
    if not self.configID and not self.searched then self:Search() end
    if not self.configID then
        Add("legacy", self.searched and "no config found" or "still looking, run the probe again in a moment")
    else
        Add("legacy", ("config %s (found by %s)"):format(tostring(self.configID), tostring(self.foundBy)))
        for _, points in ipairs(self:PointsLeft()) do
            Add("legacy points", ("tree %s, currency %s: %s left, %s spent"):format(
                tostring(points.tree), tostring(points.id), tostring(points.left), tostring(points.spent)))
        end
        for _, node in ipairs(self:Nodes()) do
            Add("legacy node", ("%d %s (spell %s): %d/%d"):format(node.nodeID,
                tostring(node.name or "?"), tostring(node.spellID), node.rank, node.maxRanks))
        end
        Add("legacy cooking", ("Master Chef node %s, yield x%.2f"):format(
            tostring(self:MasterChefNode()), self:CookingYield()))
    end
    for _, id in ipairs(self.CURRENCIES) do
        Add("legacy currency " .. id, Currency(id))
    end
    return lines
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Legacy:Changed()
    self.stale = true
    self.masterChefNode = nil
    if not self.configID and self.searched and not self.searching then
        self.searched = false
        self:Search()
    end
end

function Legacy:OnEnable()
    ns.RegisterEvent(self, "TRAIT_CONFIG_UPDATED", self.Changed)
    ns.RegisterEvent(self, "TRAIT_CONFIG_CREATED", self.Changed)
    ns.RegisterEvent(self, "TRAIT_NODE_CHANGED", self.Changed)
    -- After the game has settled, so the login stays smooth.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(10, function() self:Search() end)
    end
end
