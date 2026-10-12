-- Blackthornes Tradeskills -- Logic/CraftRequests.lua
-- A word in chat when someone in Trade asks for something you can make.
--
-- The owner said yes (2026-10-12). Tradeskills already knows every recipe
-- each of the player's characters has learned, so when a line in the Trade
-- channel asks for one of them ("LF Arcanite Bar", "WTB [Mooncloth]",
-- "anyone can make Enchant Chest - Minor Health?"), it says so once:
--
--   Bob in Trade wants [Arcanite Bar]. You can make it.
--
-- The asker's name is a player link, so a click whispers them.
--
-- What counts as asking: an asking word (LF, WTB, need, looking for,
-- anyone, who can, and German's suche, brauche, wer kann, jemand) and no
-- selling word (WTS, LFW, selling, can make, verkaufe). What is asked for:
-- an item or enchant link in the line, else the name of something one of
-- the characters makes (Recipes' own names, so a German client matches
-- German lines). An enchant also matches by its effect and slot ("minor
-- health chest") or its effect with "enchant".
--
-- Read only: nothing is saved and nothing is sent. The player's own lines
-- are skipped, and one asker is told about one item once every REPEAT_GAP.
-- "Craft requests in Trade" on the Look page (`tradeRequests`, off unless
-- ticked; the owner, 2026-10-12) and /bts requests.
--
-- Smooth play: a line without an asking word costs a few string finds; the
-- names are laid out once and again only when the characters' recipes
-- change (counted, at most every REBUILD_GAP). Chat lines inside an
-- instance can be secret values, so every read is inside a pcall.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local CraftRequests = ns.NewModule("CraftRequests")

-- One asker, one item: said again only after this many seconds.
CraftRequests.REPEAT_GAP = 15 * 60
-- The names are counted again at most this often.
CraftRequests.REBUILD_GAP = 30
-- Names shorter than this are too likely to turn up by chance.
CraftRequests.MIN_NAME = 5
-- At most this many items named from one line.
CraftRequests.MOST = 3

-- Words that ask (matched as whole words, lower case).
CraftRequests.ASK = {
    "lf", "lfc", "wtb", "need", "needs", "needed", "looking for", "anyone", "any one", "anybody",
    "who can", "can someone", "can somebody", "someone", "somebody",
    "suche", "brauche", "wer kann", "jemand", "kann jemand",
}
-- Words that sell or offer: a line with one is never an ask.
CraftRequests.SELL = {
    "wts", "lfw", "selling", "can make", "can craft", "i make", "i craft", "crafting", "tips",
    "verkaufe", "vk", "biete", "stelle her",
}

-- The Trade channel's number in the game's own list.
CraftRequests.TRADE_CHANNEL_ID = 2
-- Its name, when the client gives no number.
CraftRequests.TRADE_NAMES = { "trade", "handel" }

local function IsOn()
    return ns.Config:Get("tradeRequests") == true
end
CraftRequests.IsOn = IsOn

local function Now()
    return (type(GetTime) == "function" and GetTime()) or time()
end

--------------------------------------------------------------------------------
-- Reading a line
--------------------------------------------------------------------------------

--- Lower case, links taken out, every run of punctuation one space, and a
--- space at each end, so " lf " finds the whole word only.
function CraftRequests.Plain(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h%[(.-)%]|h", " %1 ")
    text = text:lower()
    text = text:gsub("[%p%c]+", " "):gsub("%s+", " ")
    return " " .. text .. " "
end

local function HasWord(plain, words)
    for _, word in ipairs(words) do
        if plain:find(" " .. word .. " ", 1, true) then return true end
    end
    return false
end

--- Does the line ask for something, rather than sell it?
function CraftRequests.Asks(plain)
    if HasWord(plain, CraftRequests.SELL) then return false end
    return HasWord(plain, CraftRequests.ASK)
end

--- Item and enchant IDs linked in the line.
function CraftRequests.Links(text)
    local items, spells = {}, {}
    for kind, id in text:gmatch("|H(%a+):(%d+)") do
        id = tonumber(id)
        if kind == "item" then
            items[#items + 1] = id
        elseif kind == "enchant" or kind == "spell" then
            spells[#spells + 1] = id
        end
    end
    return items, spells
end

--------------------------------------------------------------------------------
-- What the characters make
--------------------------------------------------------------------------------

local function ItemName(itemID)
    local api = rawget(_G, "C_Item")
    local get = type(api) == "table" and api.GetItemNameByID
    if type(get) ~= "function" then return nil end
    local ok, name = pcall(get, itemID)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function Plainly(name)
    return (CraftRequests.Plain(name):gsub("^ ", ""):gsub(" $", ""))
end

--- How many recipes the characters have, to tell when the names are stale.
local function RecipeCount()
    local count = 0
    for _, record in pairs(ns.db and ns.db.characters or {}) do
        if type(record) == "table" and type(record.recipes) == "table" then
            for _ in pairs(record.recipes) do count = count + 1 end
        end
    end
    return count
end

local function AddMaker(entry, characterKey)
    for _, key in ipairs(entry.makers) do
        if key == characterKey then return end
    end
    entry.makers[#entry.makers + 1] = characterKey
end

--- Lay the characters' recipes out by item, by recipe and by name.
function CraftRequests:Build()
    local byItem, byRecipe, names = {}, {}, {}
    local byName = {}
    local recipes = ns.Recipes
    for characterKey, record in pairs(ns.db and ns.db.characters or {}) do
        local key = ns.Characters and ns.Characters.Canonical and ns.Characters:Canonical(characterKey) or characterKey
        for recipeID, recipe in pairs(type(record) == "table" and type(record.recipes) == "table" and record.recipes or {}) do
            local dropped = recipes and recipes.IsDropped and recipes:IsDropped(recipe, characterKey)
            if type(recipe) == "table" and not dropped then
                local entry = byRecipe[recipeID]
                if not entry then
                    entry = { recipeID = recipeID, itemID = recipe.outputItemID, name = recipe.name, makers = {} }
                    byRecipe[recipeID] = entry
                    if entry.itemID then byItem[entry.itemID] = byItem[entry.itemID] or entry end

                    local seen = {}
                    local itemName = entry.itemID and ItemName(entry.itemID) or nil
                    for i = 1, 2 do
                        local name = i == 1 and itemName or recipe.name
                        if type(name) == "string" then
                            local plain = Plainly(name)
                            if #plain >= CraftRequests.MIN_NAME and not seen[plain] and not byName[plain] then
                                seen[plain] = true
                                byName[plain] = entry
                                names[#names + 1] = { plain = plain, entry = entry }
                            end
                        end
                    end
                    -- An enchant: "Enchant Chest - Minor Health" also
                    -- answers to its effect with its slot or "enchant".
                    if not entry.itemID and type(recipe.name) == "string" then
                        local slot, effect = recipe.name:match("^[^%-]-(%S+)%s*%-%s*(.+)$")
                        if slot and effect then
                            entry.slot = Plainly(slot)
                            entry.effect = Plainly(effect)
                        end
                    end
                end
                AddMaker(entry, key)
            end
        end
    end
    -- Longest first, so "heavy linen bandage" is taken before "linen bandage".
    table.sort(names, function(a, b)
        if #a.plain ~= #b.plain then return #a.plain > #b.plain end
        return a.plain < b.plain
    end)
    self.byItem, self.byRecipe, self.names = byItem, byRecipe, names
    self.enchants = {}
    for _, entry in pairs(byRecipe) do
        if entry.effect and #entry.effect >= CraftRequests.MIN_NAME then
            self.enchants[#self.enchants + 1] = entry
        end
    end
    table.sort(self.enchants, function(a, b)
        if #a.effect ~= #b.effect then return #a.effect > #b.effect end
        return a.recipeID < b.recipeID
    end)
    self.builtCount = RecipeCount()
    self.builtAt = Now()
end

function CraftRequests:Ready()
    if self.names and self.builtAt and Now() - self.builtAt < CraftRequests.REBUILD_GAP then return end
    if self.names and RecipeCount() == self.builtCount then
        self.builtAt = Now()
        return
    end
    self:Build()
end

--- What in the line one of the characters makes: a list of entries.
function CraftRequests:Wanted(text, plain)
    self:Ready()
    local found, taken = {}, {}
    local function Take(entry)
        if entry and not taken[entry] and #found < CraftRequests.MOST then
            taken[entry] = true
            found[#found + 1] = entry
        end
    end

    local items, spells = CraftRequests.Links(text)
    for _, itemID in ipairs(items) do Take(self.byItem[itemID]) end
    for _, spellID in ipairs(spells) do Take(self.byRecipe[spellID]) end
    if #items + #spells > 0 then return found end

    local rest = plain
    for _, name in ipairs(self.names) do
        if #found >= CraftRequests.MOST then break end
        local at = rest:find(" " .. name.plain .. " ", 1, true)
        if at then
            Take(name.entry)
            -- Blank it out, so a shorter name inside it is not found too.
            rest = rest:sub(1, at) .. string.rep("#", #name.plain) .. rest:sub(at + #name.plain + 1)
        end
    end
    local enchantWord = rest:find(" enchant", 1, true) or rest:find(" ench ", 1, true)
        or rest:find(" verzauber", 1, true)
    -- An enchant by its effect: with its slot first ("agility cloak"), and
    -- only when no slot matched, with the word "enchant" alone.
    local bySlot = false
    for _, entry in ipairs(self.enchants) do
        if rest:find(" " .. entry.effect .. " ", 1, true)
            and entry.slot and rest:find(" " .. entry.slot .. " ", 1, true) then
            bySlot = true
            Take(entry)
        end
    end
    if not bySlot and enchantWord then
        for _, entry in ipairs(self.enchants) do
            if rest:find(" " .. entry.effect .. " ", 1, true) then Take(entry) end
        end
    end
    return found
end

--------------------------------------------------------------------------------
-- Saying so
--------------------------------------------------------------------------------

local function SelfKey()
    local config = ns.Config
    if not (config and config.GetCharacterKey) then return nil end
    local ok, key = pcall(config.GetCharacterKey, config)
    if ok and type(key) == "string" then return key end
    return nil
end

local function CharacterName(characterKey)
    if ns.Recipes and ns.Recipes.GetCharacterName then
        local ok, name = pcall(ns.Recipes.GetCharacterName, ns.Recipes, characterKey)
        if ok and type(name) == "string" then return name end
    end
    return tostring(characterKey)
end

--- "You can make it.", "Bob Wither can make it.", "You and Bob Wither can
--- make it.", the character playing first, the others by full name.
function CraftRequests.WhoMakes(makers)
    local selfKey = SelfKey()
    local here, others = false, {}
    for _, key in ipairs(makers) do
        local same = key == selfKey
        if not same and ns.Characters and ns.Characters.Same and selfKey then
            local ok, answer = pcall(ns.Characters.Same, ns.Characters, key, selfKey)
            same = ok and answer and true or false
        end
        if same then
            here = true
        else
            others[#others + 1] = CharacterName(key)
        end
    end
    table.sort(others)
    if #others > 3 then
        others = { others[1], others[2], L.Format("%d more", #others - 2) }
    end
    local list = table.concat(others, ", ")
    if here and #others == 0 then return L["You can make it."] end
    if here then return L.Format("You and %s can make it.", list) end
    return L.Format("%s can make it.", list)
end

local function Shown(entry)
    if ns.Recipes and ns.Recipes.GetDisplayLink then
        local ok, link = pcall(ns.Recipes.GetDisplayLink, ns.Recipes, entry.recipeID)
        if ok and type(link) == "string" then return link end
    end
    return entry.name or tostring(entry.recipeID)
end

--- Was this asker told about this item lately? Remembers that they are now.
function CraftRequests:Fresh(sender, entry)
    local now = Now()
    self.told = self.told or {}
    -- Forget the old ones now and then, so the list stays short.
    if (self.toldSwept or 0) + CraftRequests.REPEAT_GAP < now then
        self.toldSwept = now
        for key, at in pairs(self.told) do
            if now - at >= CraftRequests.REPEAT_GAP then self.told[key] = nil end
        end
    end
    local key = sender .. "\1" .. tostring(entry.recipeID)
    local at = self.told[key]
    if at and now - at < CraftRequests.REPEAT_GAP then return false end
    self.told[key] = now
    return true
end

local function IsMe(sender, guid)
    if type(guid) == "string" and type(UnitGUID) == "function" then
        local ok, mine = pcall(UnitGUID, "player")
        if ok and mine == guid then return true end
    end
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, "player")
        if ok and type(name) == "string" and (sender == name or sender:match("^([^%-]+)") == name) then
            return true
        end
    end
    return false
end

--- One line from Trade. Returns the chat line said, or nil.
function CraftRequests:Heard(text, sender, guid)
    if not IsOn() then return nil end
    local ok, line = pcall(function()
        if type(text) ~= "string" or type(sender) ~= "string" or text == "" then return nil end
        if IsMe(sender, guid) then return nil end
        local plain = CraftRequests.Plain(text)
        if not CraftRequests.Asks(plain) then return nil end
        local wanted = self:Wanted(text, plain)
        local fresh = {}
        for _, entry in ipairs(wanted) do
            if self:Fresh(sender, entry) then fresh[#fresh + 1] = entry end
        end
        if #fresh == 0 then return nil end

        local short = sender:match("^([^%-]+)") or sender
        local who = ("|Hplayer:%s|h[%s]|h"):format(sender, short)
        local lines = {}
        for _, entry in ipairs(fresh) do
            lines[#lines + 1] = L.Format("%s in Trade wants %s. %s", who, Shown(entry), CraftRequests.WhoMakes(entry.makers))
        end
        return table.concat(lines, "\n")
    end)
    if not ok or not line then return nil end
    for part in line:gmatch("[^\n]+") do ns.Print(part) end
    return line
end

--- Is this channel line from Trade?
function CraftRequests.IsTrade(channelName, zoneChannelID, channelBaseName)
    if zoneChannelID == CraftRequests.TRADE_CHANNEL_ID then return true end
    for _, name in ipairs({ channelBaseName, channelName }) do
        if type(name) == "string" then
            local lower = name:lower()
            for _, trade in ipairs(CraftRequests.TRADE_NAMES) do
                if lower:find(trade, 1, true) then return true end
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function CraftRequests:OnEnable()
    ns.RegisterEvent(self, "CHAT_MSG_CHANNEL", function(_, _, text, sender, _, channelName, _, _,
            zoneChannelID, _, channelBaseName, _, _, guid)
        if not IsOn() then return end
        local ok, trade = pcall(CraftRequests.IsTrade, channelName, zoneChannelID, channelBaseName)
        if ok and trade then CraftRequests:Heard(text, sender, guid) end
    end)
end

ns.RegisterCommand("requests", L["say in chat when someone in Trade asks for something you can make (on or off)"], function(args)
    local word = (args or ""):lower():match("^%s*(%a+)")
    local on
    if word == "on" then
        on = true
    elseif word == "off" then
        on = false
    else
        on = not IsOn()
    end
    ns.Config:Set("tradeRequests", on)
    ns.Print(on and L["craft requests in Trade: on."] or L["craft requests in Trade: off."])
    if ns.UI and ns.UI.RefreshActiveTab then ns.UI:RefreshActiveTab() end
end)
