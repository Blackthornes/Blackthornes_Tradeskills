-- Blackthornes Tradeskills -- Logic/Wishlist.lua
-- The recipe wishlist (the owner said build it, 2026-11-17, from a mockup
-- with the words he approved). With "Recipe Wishlist:" ticked, a star on
-- each recipe to learn (Level Up's LEARN NEXT rows and Recipes to Learn)
-- puts it on this character's wishlist. A vendor or trainer that teaches a
-- starred recipe says so: a card under its window (UI/Wishlist.lua), or
-- Butler's row while Butler is loaded, and one chat line per vendor each
-- login. A starred recipe comes off once this character knows it.
--
-- Saved account wide by character, one key per character:
--   recipeWishlist[guid][recipeID] = true   (never rename it)
-- and the setting `recipeWishlistOn` (off unless ticked). With no GUID the
-- client will read (inside a dungeon), a star does nothing and nothing is
-- written. A recipe is kept under the ID the merged recipe book gives it
-- (the game's where it listed a Classic recipe under its own).
--
-- Butler reads the open vendor's or trainer's starred recipes, read only:
--   _G.BlackthornesTS.Butler:WishlistHere()   (Logic/Butler.lua)

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Wishlist = ns.NewModule("Wishlist")

local GUID_KEY = "^Player%-"

-- How long after a vendor or trainer event the list is read again: they
-- come in bursts (a buy, the trainer's filter flipped).
Wishlist.READ_DELAY = 0.2

Wishlist.version = 0

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- A client function by its dotted name, or nil.
local function Lookup(name)
    local fn = _G
    for part in name:gmatch("[^%.]+") do
        if type(fn) ~= "table" then return nil end
        fn = rawget(fn, part)
    end
    return type(fn) == "function" and fn or nil
end

--- Call a client function inside a pcall; nothing when it is missing or raises.
local function Call(name, ...)
    local fn = Lookup(name)
    if not fn then return nil end
    local function Pass(ok, ...)
        if not ok then return nil end
        return ...
    end
    return Pass(pcall(fn, ...))
end

--- A plain copy of a string the client handed over, or nil.
local function Plain(value)
    local ok, copy = pcall(function()
        if type(value) == "string" and value ~= "" then return value .. "" end
    end)
    return ok and copy or nil
end

--- A plain whole number, or nil.
local function Number(value)
    local ok, copy = pcall(function()
        local n = tonumber(value)
        if n and n == n and n ~= math.huge and n ~= -math.huge then return math.floor(n) end
    end)
    return ok and copy or nil
end

local function Book()
    return ns.RecipeBook
end

--- The recipe book's record for a recipe ID, or nil.
local function Record(recipeID)
    local book = Book()
    if not (book and book.Get and recipeID) then return nil end
    local ok, record = pcall(book.Get, book, recipeID)
    return ok and type(record) == "table" and record or nil
end

--------------------------------------------------------------------------------
-- The setting and the saved list
--------------------------------------------------------------------------------

function Wishlist:IsOn()
    return ns.Config ~= nil and ns.Config:Get("recipeWishlistOn") == true
end

function Wishlist:SetOn(on)
    if ns.Config then ns.Config:Set("recipeWishlistOn", on and true or false) end
    self:Changed()
    if on then self:ReadHere() end
end

--- The character playing's GUID, or nil when the client will not say.
function Wishlist.PlayerGUID()
    local ok, guid = pcall(function()
        local value = UnitGUID("player")
        if type(value) == "string" and value:find(GUID_KEY) then return value .. "" end
    end)
    return ok and guid or nil
end

--- This character's starred recipes, { [recipeID] = true }, or nil with no
--- GUID (or nothing saved and `create` not set).
function Wishlist:List(create)
    local guid = self.PlayerGUID()
    local db = ns.db
    if not guid or type(db) ~= "table" then return nil end
    local all = db.recipeWishlist
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}
        db.recipeWishlist = all
    end
    local mine = all[guid]
    if type(mine) ~= "table" then
        if not create then return nil end
        mine = {}
        all[guid] = mine
    end
    return mine
end

--- The ID a recipe is kept under: the merged book's, else as given.
function Wishlist.Key(recipeID)
    recipeID = Number(recipeID)
    if not recipeID then return nil end
    local record = Record(recipeID)
    return record and Number(record.recipeID) or recipeID
end

--- Is this recipe on the wishlist of the character playing?
function Wishlist:Has(recipeID)
    local list = self:List(false)
    if not list then return false end
    local key = self.Key(recipeID)
    return key ~= nil and (list[key] == true or list[Number(recipeID) or false] == true)
end

--- How many recipes the character playing has starred.
function Wishlist:Count()
    local count = 0
    for _ in pairs(self:List(false) or {}) do count = count + 1 end
    return count
end

--- Star or unstar a recipe. Nothing is written without a GUID.
-- @return true when the list changed
function Wishlist:Set(recipeID, on)
    local key = self.Key(recipeID)
    if not key then return false end
    local list = self:List(on and true or false)
    if not list then return false end
    local was = list[key] == true or list[Number(recipeID) or false] == true
    if was == (on and true or false) then return false end
    if on then
        list[key] = true
    else
        list[key] = nil
        list[Number(recipeID) or false] = nil
    end
    self:Changed()
    self:ReadHere()
    return true
end

function Wishlist:Toggle(recipeID)
    return self:Set(recipeID, not self:Has(recipeID))
end

--- Something changed: lists redraw once, the card follows.
function Wishlist:Changed()
    self.version = (self.version or 0) + 1
    if ns.UI and ns.UI.RefreshActiveTab then pcall(ns.UI.RefreshActiveTab, ns.UI) end
    if ns.WishlistCard and ns.WishlistCard.Update then pcall(ns.WishlistCard.Update, ns.WishlistCard) end
end

--- A recipe's name for chat: the book's, else the game's spell name.
function Wishlist.NameOf(recipeID)
    local record = Record(recipeID)
    local name = record and Plain(record.name)
    if name then return name end
    local info = Call("C_Spell.GetSpellInfo", recipeID)
    name = type(info) == "table" and Plain(info.name) or Plain((Call("GetSpellInfo", recipeID)))
    return name or L.Format("recipe %s", tostring(recipeID))
end

--- Take off and say so: "You learned X. It's off your wishlist now."
local function Learned(list, key)
    list[key] = nil
    ns.Print(L.Format("You learned %s. It's off your wishlist now.", Wishlist.NameOf(key)))
end

--- Take off every starred recipe the recipe book says this character knows.
-- @return how many came off
function Wishlist:Prune()
    local list = self:List(false)
    local book = Book()
    if not (list and book and book.KnowsIt) then return 0 end
    local gone = {}
    for recipeID in pairs(list) do
        local record = Record(recipeID)
        local ok, knows = pcall(book.KnowsIt, book, record)
        if record and ok and knows then gone[#gone + 1] = recipeID end
    end
    for _, recipeID in ipairs(gone) do Learned(list, recipeID) end
    if #gone > 0 then self:Changed() end
    return #gone
end

--- NEW_RECIPE_LEARNED: a starred recipe just learned comes off.
function Wishlist:OnLearned(recipeID)
    local list = self:List(false)
    recipeID = Number(recipeID)
    if not (list and recipeID) then return false end
    local key = self.Key(recipeID)
    local found = (list[key] and key) or (list[recipeID] and recipeID)
    if not found then return false end
    if found ~= key then list[key] = nil end
    Learned(list, found)
    self:Changed()
    self:ReadHere()
    return true
end

--------------------------------------------------------------------------------
-- What the open vendor or trainer teaches
--------------------------------------------------------------------------------

--- The character's skill in a book record's profession, or nil when it
--- does not have it.
function Wishlist.SkillFor(record)
    local recipes = ns.Recipes
    if not (record and record.profession and recipes and recipes.GetLearnedProfessions) then return nil end
    local ok, list = pcall(recipes.GetLearnedProfessions, recipes)
    if not ok or type(list) ~= "table" then return nil end
    for _, profession in ipairs(list) do
        local english = profession.name
        if type(recipes.EnglishProfessionName) == "function" then
            local read, name = pcall(recipes.EnglishProfessionName, profession)
            if read and name then english = name end
        end
        if english == record.profession then return Number(profession.skillLevel) end
    end
    return nil
end

--- The skill to show on the card when the character is short of it, else nil.
local function ShortOf(needs, record)
    needs = Number(needs)
    if not needs or needs <= 0 then return nil end
    local skill = Wishlist.SkillFor(record) or 0
    return skill < needs and needs or nil
end

--- The open vendor's starred recipes, in the vendor's order.
function Wishlist:ReadVendor()
    local vendor = ns.Vendor
    local book = Book()
    local found = {}
    if not (vendor and vendor.isMerchantOpen and book and book.ForItem) then return found end
    for itemID, offer in pairs(vendor.merchantRecipes or {}) do
        local ok, record = pcall(book.ForItem, book, itemID)
        if ok and type(record) == "table" and self:Has(record.recipeID) and type(offer) == "table" then
            found[#found + 1] = {
                recipeID = Number(record.recipeID), name = Plain(record.name), itemID = itemID,
                price = Number(offer.gold), needs = Number(record.skill),
                short = ShortOf(record.skill, record), kind = "vendor", index = Number(offer.index),
                costs = offer.costs,
            }
        end
    end
    table.sort(found, function(a, b) return (a.index or 999) < (b.index or 999) end)
    return found
end

--- The record a trainer's line teaches: the tooltip's spell ID when the
--- client gives it, else matched by name among starred recipes.
local function ServiceRecord(index, name, starred)
    local data = Call("C_TooltipInfo.GetTrainerService", index)
    local id = type(data) == "table" and Number(data.id) or nil
    if id and Wishlist:Has(id) then return Record(id) or { recipeID = id, name = Plain(name) } end
    name = Plain(name)
    if not name then return nil end
    local lower = name:lower()
    for recipeID in pairs(starred) do
        local record = Record(recipeID)
        if record and type(record.name) == "string" and record.name:lower() == lower then return record end
    end
    return nil
end

--- The trainer's lines that teach a starred recipe, as the trainer's
--- filter shows them now: { [recipeID] = entry }.
local function TrainerLines(starred, found, learnable)
    local count = Number(Call("GetNumTrainerServices")) or 0
    for index = 1, count do
        local name, _, kind = Call("GetTrainerServiceInfo", index)
        kind = Plain(kind)
        if kind ~= "header" and kind ~= "used" then
            local record = ServiceRecord(index, name, starred)
            local recipeID = record and Number(record.recipeID)
            if recipeID and not found[recipeID] then
                local needs = Number(record.skill)
                if not needs then
                    local _, asked = Call("GetTrainerServiceSkillReq", index)
                    needs = Number(asked)
                end
                local short = ShortOf(needs, record)
                if kind == "unavailable" and not short then short = needs end
                found[recipeID] = {
                    recipeID = recipeID, name = Plain(record.name) or Plain(name), needs = needs,
                    price = Number((Call("GetTrainerServiceCost", index))),
                    short = short, kind = "trainer",
                    -- Only a line read as the trainer shows it can be trained by place.
                    index = learnable and kind == "available" and index or nil,
                }
            end
        end
    end
end

--- The open trainer's starred recipes. Lines it hides until the skill is
--- high enough are read with its filter flipped on and then put back.
function Wishlist:ReadTrainer()
    local found = {}
    local starred = self:List(false)
    if not (starred and next(starred)) then return {} end
    if Lookup("IsTradeskillTrainer") and not Call("IsTradeskillTrainer") then return {} end

    TrainerLines(starred, found, true)
    local hidden = Lookup("GetTrainerServiceTypeFilter") and Lookup("SetTrainerServiceTypeFilter")
        and not Call("GetTrainerServiceTypeFilter", "unavailable")
    if hidden then
        self.flipping = true
        Call("SetTrainerServiceTypeFilter", "unavailable", 1)
        TrainerLines(starred, found, false)
        Call("SetTrainerServiceTypeFilter", "unavailable", 0)
        self.flipping = false
    end

    local list = {}
    for _, entry in pairs(found) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        if (a.index ~= nil) ~= (b.index ~= nil) then return a.index ~= nil end
        if a.index and b.index then return a.index < b.index end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

--- Read what the open vendor or trainer teaches, keep it as `here`, and
--- tell the card. One chat line per vendor or trainer each login.
function Wishlist:ReadHere()
    local here, kind
    if self:IsOn() and self.PlayerGUID() then
        if self.trainerOpen then
            kind = "trainer"
            local ok, list = pcall(self.ReadTrainer, self)
            here = ok and list or {}
        elseif ns.Vendor and ns.Vendor.isMerchantOpen then
            kind = "vendor"
            local ok, list = pcall(self.ReadVendor, self)
            here = ok and list or {}
        end
    end
    self.here, self.hereKind = here, kind
    if here and #here > 0 then self:SayOnce(kind, #here) end
    if ns.WishlistCard and ns.WishlistCard.Update then pcall(ns.WishlistCard.Update, ns.WishlistCard) end
    return here
end

--- "This vendor sells 2 recipes on your wishlist." and the like.
function Wishlist.CountText(kind, count)
    if kind == "trainer" then
        return count == 1 and L["This trainer teaches a recipe on your wishlist."]
            or L.Format("This trainer teaches %d recipes on your wishlist.", count)
    end
    return count == 1 and L["This vendor sells a recipe on your wishlist."]
        or L.Format("This vendor sells %d recipes on your wishlist.", count)
end

--- The chat line, once per vendor or trainer each login.
function Wishlist:SayOnce(kind, count)
    local guid = Plain((Call("UnitGUID", "npc"))) or "?"
    local npc = guid:match("^%a+%-[^%-]+%-[^%-]+%-[^%-]+%-[^%-]+%-(%d+)") or guid
    self.told = self.told or {}
    local key = kind .. ":" .. npc
    if self.told[key] then return false end
    self.told[key] = true
    ns.Print(Wishlist.CountText(kind, count))
    return true
end

--- The starred recipes the open vendor or trainer teaches, or nil.
function Wishlist:Here()
    if not self:IsOn() then return nil end
    return self.here, self.hereKind
end

--------------------------------------------------------------------------------
-- Buy and Learn, one copy a click
--------------------------------------------------------------------------------

--- Buy one copy of a starred recipe from the open vendor, by its place.
-- @return true when the buy was asked for
function Wishlist:Buy(entry)
    if not (entry and entry.kind == "vendor" and entry.index) then return false end
    if not (ns.Vendor and ns.Vendor.isMerchantOpen) then return false end
    local getID = ns.Vendor.GetMerchantItemID
    local info = Call("C_MerchantFrame.GetItemInfo", entry.index)
    local itemID = getID and select(1, getID(entry.index, type(info) == "table" and info or nil))
    -- The list moved since it was read: read it again rather than buy something else.
    if itemID ~= entry.itemID then
        self:ReadHere()
        return false
    end
    if not Lookup("BuyMerchantItem") then return false end
    return (pcall(BuyMerchantItem, entry.index, 1))
end

--- Train a starred recipe at the open trainer, by its place.
-- @return true when the training was asked for
function Wishlist:Learn(entry)
    if not (entry and entry.kind == "trainer" and entry.index and self.trainerOpen) then return false end
    local name = Plain((Call("GetTrainerServiceInfo", entry.index)))
    if not name or (entry.name and name:lower() ~= entry.name:lower()) then
        self:ReadHere()
        return false
    end
    if not Lookup("BuyTrainerService") then return false end
    return (pcall(BuyTrainerService, entry.index))
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

--- Read again a moment after the last of a burst.
function Wishlist:ReadSoon()
    if self.readTimer then return end
    if not (C_Timer and C_Timer.After) then return self:ReadHere() end
    self.readTimer = true
    C_Timer.After(Wishlist.READ_DELAY, function()
        Wishlist.readTimer = nil
        Wishlist:ReadHere()
    end)
end

function Wishlist:OnEnable()
    if not ns.RegisterEvent then return end
    -- After Data/Vendor.lua's own read, which waits as long.
    ns.RegisterEvent(self, "MERCHANT_SHOW", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function() Wishlist:Prune(); Wishlist:ReadHere() end)
        end
    end)
    ns.RegisterEvent(self, "MERCHANT_UPDATE", function() Wishlist:ReadSoon() end)
    ns.RegisterEvent(self, "MERCHANT_CLOSED", function() Wishlist:ReadHere() end)
    ns.RegisterEvent(self, "TRAINER_SHOW", function()
        Wishlist.trainerOpen = true
        Wishlist:Prune()
        Wishlist:ReadSoon()
    end)
    ns.RegisterEvent(self, "TRAINER_UPDATE", function()
        if Wishlist.flipping or not Wishlist.trainerOpen then return end
        Wishlist:ReadSoon()
    end)
    ns.RegisterEvent(self, "TRAINER_CLOSED", function()
        Wishlist.trainerOpen = false
        Wishlist:ReadHere()
    end)
    ns.RegisterEvent(self, "NEW_RECIPE_LEARNED", function(_, _, recipeID) Wishlist:OnLearned(recipeID) end)
end
