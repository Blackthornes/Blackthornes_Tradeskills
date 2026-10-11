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
--   disenchanter   the disenchanter typed in Settings (full name) when this
--                  item is gear the Mail page sends there: green up to the
--                  quality picked, can be disenchanted, does not bind when
--                  picked up, not crafted, no upgrade for the character playing
--                  (QueueMail:GoesToDisenchanter, 2026-10-11). nil with no
--                  disenchanter typed. A soulbound copy is Butler's to leave
--                  out.
--   need           how many the character playing's own queued crafts still
--                  use from its bags (what they use, less what it makes and
--                  what is in its bank), as the Mail panel works it out.
--   mailTo,        the alt whose queued crafts this character's bags can
--   mailCount      supply, and how many (QueueMail:GetDeliveries).
--   bought         how many the account bought on the auction house to
--                  disenchant (DisenchantBuys:Count, 2026-10-11), nil when
--                  none.
--
-- Butler's right-click menu marks or unmarks one (2026-10-11):
--
--   _G.BlackthornesTS.Butler:SetBoughtToDisenchant(itemID, on, count)
--     -- true, or false and why; never raises
--
-- Butler asks once per bag item, a hundred times in a burst. So the queue,
-- the mail plan and the characters' Enchanting are read once into a lookup
-- and kept until the queue changes (Queue.version), the bags change
-- (Inventory.changes) or LOOKUP_SECONDS pass, whichever comes first; it is
-- built again on the next question, never on a timer. Each question is then
-- a few table reads and the per-item prices.
--
-- Butler's "All characters" list (2026-10-10) asks one more thing, once
-- each time that list is built, never per item:
--
--   _G.BlackthornesTS.Butler:Holdings()   -- a list, or nil
--
-- One entry per character Tradeskills has a record for, the character
-- playing first (Recipes:GetCharacters' order and names):
--
--   key            "Name-Realm", as Tradeskills keys it.
--   name           the name Recipes:GetCharacters gives (told apart by
--                  level and class when two share it).
--   short          the short name (Recipes:GetShortCharacterName).
--   realm, faction as recorded, or nil.
--   isCurrent      true for the character playing.
--   linked         the character it came through when it is on another
--                  account of yours (Logic/AccountLink.lua), else nil.
--   bags, bank,    { [itemID] = count }, each a fresh copy: the bags of the
--   mail           character playing are read live (Inventory:GetBagCounts),
--                  everything else is the last snapshot.
--   bagsAt,        when each was last read (time()), nil when never; the
--   bankAt, mailAt live bags say now.
--   gold, goldAt   copper on the character when last seen, and when
--                  (the bags' snapshot time); live for the character
--                  playing. nil when never recorded (2026-10-11, for
--                  Butler's gold top-ups).
--
-- At a mailbox and the bank (2026-10-11), Butler asks two more things:
--
--   _G.BlackthornesTS.Butler:FillMail(name, items, money)   -- true, or false and why
--   _G.BlackthornesTS.Butler:FromBank()              -- { [itemID] = count }, or nil
--
-- FillMail fills the game's Send Mail page for one of the player's
-- characters (QueueMail:Fill, the same one the Mail panel uses): `name` is
-- the short name Advise gave as mailTo or enchanter, `items` a list of
-- { itemID, count }, `money` optional copper put in the gold boxes (gold
-- alone is a mail too; never with COD ticked, never more than the purse
-- less postage). The player presses Send; what goes is written down by
-- QueueMail's own SendMail hook, as for the Mail panel. FromBank says what
-- the character playing's own queued crafts still want from its bank: what
-- they use, less what it makes and what it carries, no more than its bank
-- holds.
--
-- Butler's step list for jobs on other characters (the owner asked
-- 2026-10-11 for a way to "go craft Medium Leather on another, then send it
-- back") asks two more:
--
--   _G.BlackthornesTS.Butler:Jobs()             -- a list, or nil; reads only
--   _G.BlackthornesTS.Butler:Craft(recipeID)    -- true, or false and why
--
-- Jobs is one entry per character with something to do in the queue, the
-- character playing first, then by name: { key, name (full), isCurrent,
-- steps }. Each step is a craft, { kind = "craft", recipeID, itemID, name,
-- count (items it makes), crafts, forNames (full names it is for, other
-- than the crafter), ready, missing = { { itemID, count, from } } }, or a
-- mail, { kind = "mail", to (full name), items = { { itemID, count } },
-- crafts, forCraft }: what the character playing can send now
-- (QueueMail:GetDeliveries), and for the others what they made for someone
-- and still owe (QueueMail:GetOwedBy). A craft held up for materials
-- another character carries or banks names it as the missing item's
-- `from`, and that character gets a mail step to the crafter first
-- (`forCraft`), so it can be done before the craft. Only characters this one can mail (same realm and
-- side), never another account's. Craft makes the character playing's
-- queued craft of that recipe, from Butler's click: started when its
-- profession window shows it, else the Queue tab opens on its Open button.
--
-- Butler's CLAUDE.md and its Logic/Sisters.lua lean on these calls and these
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
            and not (ns.QueueMail and ns.QueueMail.IsPlaying and ns.QueueMail:IsPlaying(characterKey))
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

--- How many the account bought to disenchant, or nil for none.
local function Bought(itemID)
    local buys = ns.DisenchantBuys
    local count = buys and buys.Count and buys:Count(itemID) or 0
    return count > 0 and count or nil
end

--- The disenchanter typed in Settings, when the Mail page sends it this item.
local function Disenchanter(itemID, kept, quality)
    local chosen, mail = kept.chosen, ns.QueueMail
    if not (chosen and mail and mail.GoesToDisenchanter) then return nil end
    if mail:GoesToDisenchanter(itemID, quality) then return chosen.name end
    return nil
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
        disenchanter = Disenchanter(itemID, kept, quality),
        need = kept.need[itemID],
        mailTo = mail and mail.name or nil,
        mailCount = mail and mail.count or nil,
        bought = Bought(itemID),
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

--- Mark an item bought to disenchant, `count` of them (at least one), or
--- take the mark off. Never raises.
-- @return true, or false and why
function Butler:SetBoughtToDisenchant(itemID, on, count)
    itemID = tonumber(itemID)
    local buys = ns.DisenchantBuys
    if not itemID or not buys then return false, "Tradeskills can't mark that." end
    local ok, err = pcall(function()
        if on then
            buys:Mark(itemID, math.max(1, tonumber(count) or 1))
        else
            buys:Unmark(itemID)
        end
    end)
    if not ok then return false, tostring(err) end
    return true
end

--------------------------------------------------------------------------------
-- Every character's bags, bank and mail, for Butler's All characters list
--------------------------------------------------------------------------------

--- A copy of an { [itemID] = count } table, keeping only real counts.
local function Counts(counts)
    local copy = {}
    if type(counts) ~= "table" then return copy end
    for itemID, count in pairs(counts) do
        if type(itemID) == "number" and type(count) == "number" and count > 0 then
            copy[itemID] = count
        end
    end
    return copy
end

local function Stamp(value)
    return type(value) == "number" and value or nil
end

local function LiveBags()
    local inventory = ns.Inventory
    if not (inventory and inventory.GetBagCounts) then return nil end
    local ok, live = pcall(inventory.GetBagCounts, inventory)
    if ok and type(live) == "table" then return live end
    return nil
end

local function Holdings()
    local list = {}
    local records = Characters()
    local recipes = ns.Recipes
    if not (recipes and recipes.GetCharacters) then return list end

    for _, character in ipairs(recipes:GetCharacters()) do
        local record = records[character.key]
        if type(record) == "table" then
            local entry = {
                key = character.key,
                name = character.name,
                short = ShortName(character.key),
                realm = type(record.realm) == "string" and record.realm or nil,
                faction = type(record.faction) == "string" and record.faction or nil,
                isCurrent = character.isCurrent == true,
                linked = character.linkedFrom,
                bank = Counts(record.bank),
                mail = Counts(record.mail),
                bankAt = Stamp(record.bankAt),
                mailAt = Stamp(record.mailAt),
            }
            -- Gold as last seen, for Butler's gold top-ups (2026-10-11):
            -- the character playing's purse is live.
            entry.gold = type(record.gold) == "number" and record.gold or nil
            entry.goldAt = entry.gold and Stamp(record.inventoryAt) or nil
            if entry.isCurrent and type(GetMoney) == "function" then
                local okMoney, money = pcall(function() return tonumber(GetMoney()) end)
                if okMoney and money then
                    entry.gold = money
                    entry.goldAt = type(time) == "function" and time() or entry.goldAt
                end
            end
            local live = entry.isCurrent and LiveBags()
            if live then
                entry.bags = Counts(live)
                entry.bagsAt = type(time) == "function" and time() or Stamp(record.inventoryAt)
            else
                entry.bags = Counts(record.inventory)
                entry.bagsAt = Stamp(record.inventoryAt)
            end
            list[#list + 1] = entry
        end
    end
    return list
end

--- What every character on record carries, banks and has waiting in the
-- mail, for Butler. Never raises, writes nothing; nil when anything goes
-- wrong. Fresh tables each time, so Butler may keep or change them.
function Butler:Holdings()
    local ok, list = pcall(Holdings)
    if ok then return list end
    return nil
end

--------------------------------------------------------------------------------
-- The mailbox and the bank, for Butler
--------------------------------------------------------------------------------

--- The character a short name from Advise or Holdings means: the one whose
-- ShortName is exactly `name`, or nil when none is. A short name can be
-- "Ana B." when two characters share a first name, which
-- QueueMail:FindCharacter cannot read back (the mail went to "Ana B.").
-- More than one record can give the same short name (a character kept
-- under two keys, or a linked copy), so of those the best is taken: one of
-- this account's own, on this realm, then the lowest key. The character
-- playing, under any of its records, is never the answer.
local function CharacterNamed(name)
    local selfRecord = Characters()[SelfKey() or ""]
    local realm = type(selfRecord) == "table" and selfRecord.realm or nil

    -- "Ana S." also matches any "Ana S..." by full name, in case the short
    -- names were worked out differently when Advise gave this one.
    local first, initial = name:match("^(%S+) (%S+)%.$")
    local prefix = first and (first .. " " .. initial)
    local recipes = ns.Recipes
    local function Matches(characterKey)
        if ShortName(characterKey) == name then return true end
        if not (prefix and recipes and recipes.GetCharacterName) then return false end
        local ok, full = pcall(recipes.GetCharacterName, recipes, characterKey)
        return ok and type(full) == "string" and full:sub(1, #prefix) == prefix
    end

    local mail = ns.QueueMail
    local function Playing(characterKey)
        return mail and mail.IsPlaying and mail:IsPlaying(characterKey) == true
    end

    local best, bestScore
    for characterKey, record in pairs(Characters()) do
        if type(record) == "table" and not Playing(characterKey) and Matches(characterKey) then
            local score = (record.linkedFrom == nil and 2 or 0)
                + ((realm and record.realm == realm) and 1 or 0)
            if not best or score > bestScore
                or (score == bestScore and tostring(characterKey) < tostring(best)) then
                best, bestScore = characterKey, score
            end
        end
    end
    return best
end

--- Fill the game's Send Mail page for one of the player's characters.
-- `name` is a short name (as Advise gives it) or a name typed in Settings;
-- `items` is a list of { itemID, count }. Nothing is sent: the player
-- presses Send. Never raises. Never fills a mail to the character playing
-- (a player found one, 2026-10-11): that is "false" and why.
-- @return true when filling started, or false and why; then the name the
--   mail is addressed to, in full
function Butler:FillMail(name, items, money)
    local mail = ns.QueueMail
    if not (mail and mail.Fill) then return false, "Tradeskills cannot fill mail here" end
    if type(name) ~= "string" or name == "" then return false, "nobody to mail" end
    money = tonumber(money)
    money = money and money >= 1 and math.floor(money) or nil
    if type(items) ~= "table" then items = {} end
    if #items == 0 and not money then return false, "nothing to mail" end

    local list = {}
    for _, item in ipairs(items) do
        local itemID = type(item) == "table" and tonumber(item.itemID)
        local count = type(item) == "table" and tonumber(item.count)
        if itemID and count and count > 0 then
            list[#list + 1] = { itemID = itemID, count = math.floor(count) }
        end
    end
    if #list == 0 and not money then return false, "nothing to mail" end

    local toSelf = "that's the character you're on"
    local recipient
    local ok, started, why = pcall(function()
        local key = CharacterNamed(name) or (mail.FindCharacter and mail:FindCharacter(name))
        if key == nil and mail.IsPlayingName and mail:IsPlayingName(name) then return false, toSelf end
        if key ~= nil and mail.IsPlaying and mail:IsPlaying(key) then return false, toSelf end
        recipient = key and mail.MailName and mail.MailName(Characters()[key]) or name
        if mail.IsPlayingName and mail:IsPlayingName(recipient) then return false, toSelf end
        return mail:Fill({ recipient = recipient, items = list, money = money,
            subject = #list == 0 and "Gold from Blackthornes Butler" or "From Blackthornes Butler" })
    end)
    if not ok then return false, "Tradeskills could not fill the mail" end
    if started == true then return true, nil, recipient end
    return false, why
end

local function FromBank()
    local wants = {}
    local selfKey = SelfKey()
    local mail, inventory = ns.QueueMail, ns.Inventory
    if not (selfKey and mail and mail.GetPlan and inventory) then return wants end

    local uses, makes = mail:GetPlan()
    local myUse, myMake = uses[selfKey] or {}, makes[selfKey] or {}
    for itemID, used in pairs(myUse) do
        local carried = inventory.GetBagCount and inventory:GetBagCount(itemID) or 0
        local banked = inventory.GetBankCount and inventory:GetBankCount(itemID) or 0
        local short = used - (myMake[itemID] or 0) - carried
        local take = math.min(short, banked)
        if take > 0 then wants[itemID] = take end
    end
    return wants
end

--- What the character playing's own queued crafts want from its bank:
-- { [itemID] = count }. Never raises, writes nothing; nil on any error.
function Butler:FromBank()
    local ok, wants = pcall(FromBank)
    if ok then return wants end
    return nil
end

--------------------------------------------------------------------------------
-- Jobs across characters, for Butler's step list
--------------------------------------------------------------------------------

local function FullName(characterKey)
    local recipes = ns.Recipes
    if recipes and recipes.GetCharacterName then
        local ok, name = pcall(recipes.GetCharacterName, recipes, characterKey)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return tostring(characterKey)
end

local function ItemList(counts)
    local list = {}
    for itemID, count in pairs(type(counts) == "table" and counts or {}) do
        if type(itemID) == "number" and type(count) == "number" and count > 0 then
            list[#list + 1] = { itemID = itemID, count = count }
        end
    end
    table.sort(list, function(a, b) return a.itemID < b.itemID end)
    return list
end

local function Fold(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if text == "" then return nil end
    return text:lower()
end

-- Are two records the same character? One may be the old name-realm
-- record left beside the GUID one (Config:AdoptLegacyCharacter): it names
-- the same first name and realm, with no last name, or the same one.
local function SameCharacter(records, a, b)
    if a == b then return true end
    local one, two = records[a], records[b]
    if type(one) ~= "table" or type(two) ~= "table" then return false end
    if one.guid == b or two.guid == a then return true end
    local guidKey = "^Player%-"
    if tostring(a):find(guidKey) and tostring(b):find(guidKey) then return false end
    if not Fold(one.name) or Fold(one.name) ~= Fold(two.name) then return false end
    if one.realm and two.realm and one.realm:gsub("%s", "") ~= two.realm:gsub("%s", "") then return false end
    if one.faction and two.faction and one.faction ~= two.faction then return false end
    local s1, s2 = Fold(one.surname), Fold(two.surname)
    if s1 and s2 then return s1 == s2 end
    return true
end

-- The other character holding the most of an item in its bags and bank,
-- never the character playing (its own mail is the Mail panel's) nor
-- another account's. The key and how many, or nil.
local function Holder(records, crafterKey, itemID, Playing)
    local bestKey, bestCount = nil, 0
    for key, record in pairs(records) do
        if key ~= crafterKey and type(record) == "table" and not record.linkedFrom and not Playing(key) then
            local count = 0
            if type(record.inventory) == "table" then count = count + (tonumber(record.inventory[itemID]) or 0) end
            if type(record.bank) == "table" then count = count + (tonumber(record.bank[itemID]) or 0) end
            if count > bestCount or (count == bestCount and count > 0 and tostring(key) < tostring(bestKey)) then
                bestKey, bestCount = key, count
            end
        end
    end
    if bestKey then return bestKey, bestCount end
    return nil
end

local function Jobs()
    local list = {}
    local queue, mail = ns.Queue, ns.QueueMail
    local selfKey = SelfKey()
    if not (selfKey and queue and queue.GetAll and queue.GetCrafter and ns.Recipes) then return list end

    local records = Characters()
    local byKey = {}
    local function Playing(characterKey)
        return characterKey == selfKey
            or (mail and mail.IsPlaying and mail:IsPlaying(characterKey) == true)
    end

    -- A character's entry, made the first time it has a step. The character
    -- playing, under any of its records, is one entry.
    local function Job(characterKey)
        local playing = Playing(characterKey)
        local key = playing and selfKey or characterKey
        if byKey[key] then return byKey[key] end
        local record = records[key]
        if type(record) ~= "table" or record.linkedFrom then return nil end
        if not playing and not queue:CanMail(selfKey, key) then return nil end
        local job = { key = key, name = FullName(key), isCurrent = playing, steps = {} }
        byKey[key] = job
        return job
    end

    for _, entry in ipairs(queue:GetAll()) do
        local recipe = type(entry) == "table" and ns.Recipes:GetAny(entry.recipeID)
        local crafts = type(entry) == "table" and tonumber(entry.quantity) or 0
        if recipe and crafts > 0 then
            local crafter = queue:GetCrafter(entry)
            local job = crafter and Job(crafter)
            if job then
                local forNames = {}
                for _, characterKey in ipairs(queue:GetRecipients(entry)) do
                    if not Playing(characterKey) or not job.isCurrent then
                        forNames[#forNames + 1] = FullName(characterKey)
                    end
                end
                local missing = {}
                for _, reagent in ipairs(recipe.reagents or {}) do
                    local want = (reagent.quantity or 0) * crafts
                    local held = queue:HeldBy(job.key, reagent.itemID) or 0
                    if want > held then
                        missing[#missing + 1] = { itemID = reagent.itemID, count = want - held }
                    end
                end
                job.steps[#job.steps + 1] = {
                    kind = "craft",
                    recipeID = entry.recipeID,
                    itemID = recipe.outputItemID,
                    name = recipe.name,
                    crafts = crafts,
                    count = crafts * math.max(1, recipe.quantityMin or 1),
                    forNames = forNames,
                    ready = #missing == 0,
                    missing = missing,
                }
            end
        end
    end

    -- A craft held up for materials another character has: that character
    -- mails them over first, so its line can come first in Butler (the
    -- owner, 2026-10-11: a sub-craft whose materials are on hand goes to
    -- the top). An old name-realm record of the crafter itself counts as
    -- the crafter's own.
    local blocked = {}
    for _, job in pairs(byKey) do
        for _, step in ipairs(job.steps) do
            if step.kind == "craft" and not step.ready then blocked[#blocked + 1] = { job = job, step = step } end
        end
    end
    table.sort(blocked, function(a, b)
        if a.job.name ~= b.job.name then return a.job.name < b.job.name end
        return (a.step.recipeID or 0) < (b.step.recipeID or 0)
    end)
    for _, item in ipairs(blocked) do
        local job, step = item.job, item.step
        local still = {}
        for _, need in ipairs(step.missing) do
            local holderKey, holderCount = Holder(records, job.key, need.itemID, Playing)
            if holderKey and SameCharacter(records, holderKey, job.key) then
                need.count = need.count - holderCount
                if need.count > 0 then still[#still + 1] = need end
            else
                still[#still + 1] = need
                local holder = holderKey and queue:CanMail(holderKey, job.key) and Job(holderKey)
                if holder then
                    local count = math.min(holderCount, need.count)
                    need.from = holder.name
                    local to = job.name
                    local letter
                    for _, other in ipairs(holder.steps) do
                        if other.kind == "mail" and other.to == to and other.forCraft then letter = other end
                    end
                    if not letter then
                        letter = { kind = "mail", to = to, items = {}, crafts = false, forCraft = true }
                        table.insert(holder.steps, 1, letter)
                    end
                    letter.items[#letter.items + 1] = { itemID = need.itemID, count = count }
                end
            end
        end
        step.missing = still
        step.ready = #still == 0
    end

    -- What the character playing can mail now, as the Mail panel has it.
    if mail and mail.GetDeliveries then
        local job = Job(selfKey)
        for _, delivery in ipairs(job and mail:GetDeliveries() or {}) do
            local items = {}
            for _, item in ipairs(delivery.items or {}) do
                items[#items + 1] = { itemID = item.itemID, count = item.count }
            end
            if #items > 0 then
                job.steps[#job.steps + 1] = { kind = "mail", to = FullName(delivery.to),
                    items = items, crafts = delivery.crafts == true }
            end
        end
    end

    -- The others: what they made for someone and still owe.
    if mail and mail.GetOwedBy then
        local keys = {}
        for characterKey in pairs(records) do keys[#keys + 1] = characterKey end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, fromKey in ipairs(keys) do
            if not Playing(fromKey) then
                local owed = mail:GetOwedBy(fromKey)
                local targets = {}
                for toKey in pairs(owed) do targets[#targets + 1] = toKey end
                table.sort(targets, function(a, b) return tostring(a) < tostring(b) end)
                for _, toKey in ipairs(targets) do
                    local items = ItemList(owed[toKey])
                    local job = #items > 0 and toKey ~= fromKey and Job(fromKey)
                    if job then
                        job.steps[#job.steps + 1] = { kind = "mail", to = FullName(toKey),
                            items = items, crafts = true }
                    end
                end
            end
        end
    end

    for _, job in pairs(byKey) do
        if #job.steps > 0 then list[#list + 1] = job end
    end
    table.sort(list, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

--- Every character's jobs in the queue, for Butler's step list. Never
--- raises, writes nothing; nil on any error. Fresh tables each time.
function Butler:Jobs()
    local ok, list = pcall(Jobs)
    if ok then return list end
    return nil
end

--- Make the character playing's queued craft of a recipe, from Butler's
--- click (a craft needs a real click, and Butler's is one). Started when
--- the profession window shows the recipe; otherwise the Queue tab opens,
--- where the Open button opens the profession. Never raises.
-- @return true and "crafting" or "opened", or false and why
function Butler:Craft(recipeID)
    recipeID = tonumber(recipeID)
    if not recipeID then return false, "nothing to craft" end
    local ok, done, why = pcall(function()
        local queue, crafting = ns.Queue, ns.Crafting
        local selfKey = SelfKey()
        local entry
        for _, queued in ipairs(queue:GetAll()) do
            if queued.recipeID == recipeID and (tonumber(queued.quantity) or 0) > 0
                and queue:GetCrafter(queued) == selfKey then
                entry = queued
                break
            end
        end
        if not entry then return false, "it's no longer in your queue" end
        local ready, reason = crafting:GetReadiness(recipeID)
        if not ready then return false, reason end
        if crafting:IsBusy() then return false, "already crafting" end
        local opener = ns.ProfessionOpener
        local shows = crafting.isTradeSkillOpen
            and (not (opener and opener.WindowShowsRecipe) or opener:WindowShowsRecipe(recipeID))
        if shows then
            if crafting:Start(recipeID, entry.quantity) then return true, "crafting" end
            return false, "the game didn't start it"
        end
        if queue:ShowQueue() then return true, "opened" end
        return false, "open your profession first"
    end)
    if not ok then return false, "Tradeskills could not start the craft" end
    return done == true, why
end

--- Butler takes over the mailbox (the owner picked it, 2026-10-11): while
-- its window is up at a mailbox it says `covered` true, and the mail panel
-- beside the mailbox (UI/QueueMailPanel.lua) steps aside; false brings it
-- back. Never raises.
function Butler:Mailbox(covered)
    pcall(function()
        local panel = ns.QueueMailPanel
        if not panel then return end
        panel.coveredByButler = covered == true
        if panel.coveredByButler then
            if panel.frame then panel.frame:Hide() end
        else
            panel:Refresh()
        end
    end)
end
