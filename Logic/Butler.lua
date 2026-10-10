-- Blackthornes Tradeskills -- Logic/Butler.lua
-- What Tradeskills knows about one item, for Blackthornes Butler (2026-10-10).
--
-- Butler tells the player what to do with each item in the bags: keep it,
-- sell it, post it, disenchant it, mail it to an alt. It asks this, inside a
-- pcall and read only:
--
--   _G.BlackthornesTS.Butler:Advise(itemID)   -- a table, or nil
--
-- Every field may be nil when it is not known:
--
--   auction        copper for one, sold on the auction house, after the cut
--                  and the deposit (Profit:NetFromListing on the smoothed
--                  market price). nil for greys (vendor only), gear that
--                  binds when picked up, and items never priced.
--   fast           true when it sells well (Demand "high"), false when it
--                  rarely sells ("low"), nil in between or with no data.
--   disenchant     copper a disenchant of one is likely to give
--                  (Disenchant:GetValue), nil when it cannot be broken or
--                  its material has no price.
--   canDisenchant  true when the character playing knows Disenchant and has
--                  the Enchanting skill this one needs; false when not, or
--                  when it cannot be disenchanted at all.
--   enchanter      when the character playing cannot: the short name of the
--                  disenchanter typed in Settings, else of the alt on this
--                  account (same realm and faction) with the most Enchanting
--                  that is enough.
--   need           how many the character playing's own queued crafts still
--                  use from its bags (what they use, less what it makes and
--                  what is in its bank), as the Mail panel works it out.
--   mailTo,        the alt whose queued crafts this character's bags can
--   mailCount      supply, and how many (QueueMail:GetDeliveries).
--
-- Butler asks once per bag item, a hundred times in a burst. So the queue,
-- the mail plan and the characters' Enchanting are read once into a lookup
-- and kept until the queue changes (Queue.version), the bags change
-- (Inventory.changes) or LOOKUP_SECONDS pass, whichever comes first; it is
-- built again on the next question, never on a timer. Each question is then
-- a few table reads and the per-item prices.
--
-- Butler's CLAUDE.md and its Logic/Sisters.lua lean on this call and these
-- fields: keep them stable, or change both repos together.

local _, ns = ...

local Butler = ns.NewModule("Butler")

-- How long a lookup is trusted when nothing says it changed: mail sent, a
-- bank visit or an alt's record are not counted by any version.
local LOOKUP_SECONDS = 2

local GREY = 0

local lookup, lookupKey, lookupAt

local function Now()
    return type(GetTime) == "function" and GetTime() or 0
end

local function SelfKey()
    local config = ns.Config
    return config and config.GetCharacterKey and config:GetCharacterKey() or nil
end

local function Characters()
    local characters = ns.db and ns.db.characters
    return type(characters) == "table" and characters or {}
end

--- A character's Enchanting skill, or nil when it has none on record.
local function EnchantingSkill(record)
    if type(record) ~= "table" then return nil end
    for _, profession in ipairs(type(record.professions) == "table" and record.professions or {}) do
        if type(profession) == "table" and profession.name == "Enchanting"
            and profession.learned ~= false then
            return tonumber(profession.skillLevel) or 0
        end
    end
    return nil
end

local function ShortName(characterKey)
    local recipes = ns.Recipes
    if recipes and recipes.GetShortCharacterName then
        local ok, name = pcall(recipes.GetShortCharacterName, recipes, characterKey)
        if ok and type(name) == "string" then return name end
    end
    return characterKey
end

--- What this character's own crafts use from its bags: { [itemID] = units }.
-- The same sum QueueMail:GetDeliveries keeps back before it offers any to
-- an alt.
local function OwnNeeds(selfKey)
    local needs = {}
    local mail = ns.QueueMail
    if not (selfKey and mail and mail.GetPlan and ns.Queue and ns.Queue.GetAll) then return needs end

    local uses, makes = mail:GetPlan()
    local myUse, myMake = uses[selfKey] or {}, makes[selfKey] or {}
    local inventory = ns.Inventory

    for itemID, used in pairs(myUse) do
        local bank = inventory and inventory.GetBankCount and inventory:GetBankCount(itemID) or 0
        local left = used - (myMake[itemID] or 0) - bank
        if left > 0 then needs[itemID] = left end
    end
    return needs
end

--- For each item, the alt the bags can best supply: { [itemID] = { name, count } }.
local function MailTargets()
    local targets = {}
    local mail = ns.QueueMail
    if not (mail and mail.GetDeliveries) then return targets end

    for _, delivery in ipairs(mail:GetDeliveries() or {}) do
        for _, item in ipairs(delivery.items or {}) do
            local best = targets[item.itemID]
            if not best or item.count > best.count then
                targets[item.itemID] = { name = ShortName(delivery.to), count = item.count }
            end
        end
    end
    return targets
end

--- The alts on this account that can be mailed and have Enchanting, most
--- skill first: { { name, skill } }.
local function Enchanters(selfKey)
    local list = {}
    local queue = ns.Queue
    for characterKey, record in pairs(Characters()) do
        local skill = EnchantingSkill(record)
        if skill and characterKey ~= selfKey and record.linkedFrom == nil
            and (not (queue and queue.CanMail) or queue:CanMail(selfKey, characterKey)) then
            list[#list + 1] = { name = ShortName(characterKey), skill = skill }
        end
    end
    table.sort(list, function(a, b)
        if a.skill ~= b.skill then return a.skill > b.skill end
        return a.name < b.name
    end)
    return list
end

--- The disenchanter typed in Settings: { name, skill (nil when unknown),
--- quality (the best one mailed) }, or nil.
local function Chosen()
    local mail = ns.QueueMail
    if not (mail and mail.GetDisenchanter) then return nil end
    local typed = mail:GetDisenchanter()
    if not typed then return nil end

    local key = mail.FindCharacter and mail:FindCharacter(typed)
    local record = key and Characters()[key]
    return {
        name = record and ShortName(key) or typed,
        -- Known only for one of your own characters; one on another account
        -- was picked by the player, who knows what it can break.
        skill = record and EnchantingSkill(record) or nil,
        known = record ~= nil,
        quality = mail.GetDisenchantQuality and mail:GetDisenchantQuality() or 4,
    }
end

--- Does the character playing know Disenchant? nil when the client will not say.
local function KnowsDisenchant()
    local disenchanter = ns.Disenchanter
    if disenchanter and disenchanter.Knows then
        local ok, known = pcall(disenchanter.Knows, disenchanter)
        if ok then return known end
    end
    return nil
end

local function Build()
    local selfKey = SelfKey()
    return {
        need = OwnNeeds(selfKey),
        mail = MailTargets(),
        selfSkill = EnchantingSkill(Characters()[selfKey]),
        knows = KnowsDisenchant(),
        enchanters = Enchanters(selfKey),
        chosen = Chosen(),
    }
end

--- The kept lookup, built again when the queue or bags moved or it is old.
local function Lookup()
    local key = ("%s:%s"):format(tostring(ns.Queue and ns.Queue.version),
        tostring(ns.Inventory and ns.Inventory.changes))
    local now = Now()
    if lookup and lookupKey == key and (now - lookupAt) < LOOKUP_SECONDS then
        return lookup
    end
    lookup, lookupKey, lookupAt = Build(), key, now
    return lookup
end

--- Forget the kept lookup (for tests).
function Butler:Forget()
    lookup, lookupKey, lookupAt = nil, nil, nil
end

--------------------------------------------------------------------------------
-- The answer
--------------------------------------------------------------------------------

local function Quality(itemID)
    local facts = ns.Disenchant and ns.Disenchant.GetItemFacts and ns.Disenchant:GetItemFacts(itemID)
    if facts and facts.quality then return facts.quality end

    if type(C_Item) == "table" and type(C_Item.GetItemQualityByID) == "function" then
        local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
        if ok then return tonumber(quality) end
    end
    return nil
end

local function Auction(itemID, quality)
    if quality == nil or quality == GREY then return nil end
    local util = ns.Util
    if util and util.IsBoundOnPickup and util.IsBoundOnPickup(itemID) == true then return nil end

    local price = ns.Prices and ns.Prices:GetValue(itemID, "market")
    if not price or price <= 0 then return nil end

    local net = ns.Profit:NetFromListing(itemID, price)
    return math.max(0, math.floor(net + 0.5))
end

local function Fast(itemID)
    local reading = ns.Demand and ns.Demand:Get(itemID)
    if not reading then return nil end
    if reading.level == "high" then return true end
    if reading.level == "low" then return false end
    return nil
end

--- Can this character break it, and if not, who can?
-- @return disenchant, canDisenchant, enchanter
local function Breaking(itemID, kept, quality)
    local disenchant = ns.Disenchant
    if not disenchant then return nil, nil, nil end

    local able = disenchant:IsDisenchantable(itemID)
    if able == nil then return nil, nil, nil end
    if not able then return nil, false, nil end

    local value, _, breakdown = disenchant:GetValue(itemID)
    local needs = breakdown and breakdown.facts and breakdown.facts.skill

    local function Enough(skill)
        return skill ~= nil and (needs == nil or skill >= needs)
    end

    -- Knowing the spell with no skill on record yet counts as able.
    local can = kept.knows ~= false
        and (Enough(kept.selfSkill) or (kept.selfSkill == nil and kept.knows == true))
    if can then return value, true, nil end

    local chosen = kept.chosen
    if chosen and (quality == nil or quality <= chosen.quality)
        and (not chosen.known or Enough(chosen.skill)) then
        return value, false, chosen.name
    end

    for _, alt in ipairs(kept.enchanters) do
        if Enough(alt.skill) then return value, false, alt.name end
    end
    return value, false, nil
end

local function Answer(itemID)
    local kept = Lookup()
    local quality = Quality(itemID)
    local disenchant, canDisenchant, enchanter = Breaking(itemID, kept, quality)
    local mail = kept.mail[itemID]

    return {
        auction = Auction(itemID, quality),
        fast = Fast(itemID),
        disenchant = disenchant,
        canDisenchant = canDisenchant,
        enchanter = enchanter,
        need = kept.need[itemID],
        mailTo = mail and mail.name or nil,
        mailCount = mail and mail.count or nil,
    }
end

--- Everything Tradeskills can say about one item, for Butler.
-- Never raises, writes nothing; nil when the item ID is not one or anything
-- goes wrong. A fresh table each time, so Butler may keep or change it.
function Butler:Advise(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local ok, answer = pcall(Answer, itemID)
    if ok then return answer end
    return nil
end
