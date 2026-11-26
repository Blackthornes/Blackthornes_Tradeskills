-- Blackthornes Tradeskills -- Logic/Today.lua
-- The Today tab (the owner said build it, 2026-11-26, from a mockup): one
-- first tab that lists what is worth doing right now, best first, each line
-- with one button. UI/Tab_Today.lua draws it.
--
-- Nothing new is worked out here. Each line reads what another part of the
-- addon already knows, inside a pcall, and a part that is missing or fails
-- leaves its line out:
--
--   mail      sales the game told you about whose mail you have not taken
--             (Mail:SettleHeard), the character playing's only
--   undercut  your auctions someone has gone under (MyAuctions:Rows)
--   ready     a cooldown craft that is up on the character playing
--             (Cooldowns:ReadyList), not yet queued
--   soldout   a craft with its own Keep in Stock number that has none
--             left anywhere and none queued (Auctions:GetRoom)
--   profit    crafts the Profit tab would list (Profit:GetRanked in
--             slices), with the best profit
--   writs     Craftsman's Writs that pay back more than they cost and are
--             not done today (Writs:GetRows)
--   road      the next stretch of Road to 300 (RoadPlan:Get)
--
-- Every button only opens a tab or queues; nothing is bought, posted or made.
-- A line kind can be turned off on the Windows page; each is saved as
-- `todayHide_<kind>` (true hides it; never rename them).

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Today = {}
ns.Today = Today

-- Line kinds, in the order they show.
Today.KINDS = { "mail", "undercut", "ready", "soldout", "profit", "writs", "road" }

-- At most this many lines of one kind (sold out, cooldowns, road).
Today.MOST_EACH = 3

-- How many recipes the Profit ranking analyses a frame.
Today.BUDGET = 20

local function Try(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    if ns.Debug then ns.Debug("today:", tostring(a)) end
    return nil
end

local function Now()
    return type(time) == "function" and time() or 0
end

function Today.SettingKey(kind)
    return "todayHide_" .. kind
end

function Today:IsShown(kind)
    local config = ns.Config
    if not (config and config.Get) then return true end
    return config:Get(Today.SettingKey(kind)) ~= true
end

function Today:SetShown(kind, on)
    if not (ns.Config and ns.Config.Set) then return end
    -- Only a box that changes is written; shown is the same as never set.
    local was = self:IsShown(kind)
    if was == (on and true or false) then return end
    ns.Config:Set(Today.SettingKey(kind), (not on) and true or nil)
end

local function Playing(key)
    local characters = ns.Characters
    if characters and characters.IsPlaying then
        local ok, yes = pcall(characters.IsPlaying, characters, key)
        if ok then return yes == true end
    end
    return false
end

--------------------------------------------------------------------------------
-- The four cards along the top
--------------------------------------------------------------------------------

--- @return { goldToday, upCount, upWorth, soldToday, pricesAt }
function Today:Cards()
    local cards = {}

    local log = ns.GoldLog
    if log and log.Bins and log.Totals then
        local totals = Try(function() return log:Totals(log:Bins("today")) end)
        cards.goldToday = type(totals) == "table" and totals.net or nil
    end

    local tracker = ns.AuctionTracker
    if tracker and tracker.Rows then
        local rows = Try(tracker.Rows, tracker)
        if type(rows) == "table" then
            local count, worth = 0, 0
            for _, row in ipairs(rows) do
                count = count + 1
                worth = worth + (tonumber(row.unit) or 0) * (tonumber(row.quantity) or 1)
            end
            cards.upCount, cards.upWorth = count, worth
        end
    end
    if tracker and tracker.SoldToday then
        local _, count = Try(tracker.SoldToday, tracker)
        cards.soldToday = tonumber(count) or 0
    end

    local prices = ns.Prices
    if prices and prices.GetLastScan then
        cards.pricesAt = Try(prices.GetLastScan, prices)
    end
    return cards
end

--------------------------------------------------------------------------------
-- Item names
--------------------------------------------------------------------------------

-- Items whose name the game had not loaded when a line was made. When one
-- comes in, the tab is told once (coalesced), so "item 5764" never stays.
local unnamed = {}
local onNamed          -- the tab's redraw, from the last Lines call
local namedSoon = false

local function NameFromLink(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("|h%[(.-)%]|h")
    if name and name ~= "" then return name end
end

--- An item's name in its colour, else a name the addon already holds (the
--- recipe's, a link's, one saved before), else "item 1234". The second
--- value is true when the game's own name was not ready yet.
function Today.ItemName(itemID, ...)
    local getInfo = (type(C_Item) == "table" and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    local name, quality
    if itemID and type(getInfo) == "function" then
        local ok, a, _, c = pcall(getInfo, itemID)
        if ok then name, quality = a, c end
    end
    if type(name) == "string" and name ~= "" then
        if ns.Util and ns.Util.ColorItemName then
            local colored = Try(ns.Util.ColorItemName, itemID, name, quality)
            if type(colored) == "string" and colored ~= "" then return colored, false end
        end
        return name, false
    end
    if itemID then
        unnamed[itemID] = true
        if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
            Try(C_Item.RequestLoadItemDataByID, itemID)
        end
    end
    for index = 1, select("#", ...) do
        local known = select(index, ...)
        if type(known) == "string" and known ~= "" then
            return NameFromLink(known) or known, true
        end
    end
    local disenchant = ns.Disenchant
    if itemID and disenchant and disenchant.KnownName then
        local known = Try(disenchant.KnownName, disenchant, itemID)
        if type(known) == "string" and known ~= "" then return known, true end
    end
    return itemID and L.Format("item %d", itemID) or "?", true
end

--- The game sent an item's data: redraw once if a line was waiting on it.
function Today.OnItemInfo(itemID)
    if not (itemID and unnamed[itemID]) then return end
    unnamed[itemID] = nil
    if namedSoon or not onNamed then return end
    namedSoon = true
    local after = rawget(_G, "C_Timer") and C_Timer.After
    local function Go()
        namedSoon = false
        if onNamed then pcall(onNamed) end
    end
    if type(after) == "function" then after(0.2, Go) else Go() end
end

if ns.RegisterEvent then
    ns.RegisterEvent(Today, "GET_ITEM_INFO_RECEIVED", function(_, _, itemID)
        Today.OnItemInfo(itemID)
    end)
end

--------------------------------------------------------------------------------
-- Lines
--------------------------------------------------------------------------------

local builders = {}

-- Sales heard in chat whose mail is still in the box. The gold arrives with
-- the mail, so no amount is shown.
function builders.mail(out)
    local mail = ns.Mail
    if not (mail and mail.SettleHeard) then return end
    local waiting = Try(mail.SettleHeard, mail)
    if type(waiting) ~= "table" then return end
    local count, itemID = 0, nil
    for _, heard in ipairs(waiting) do
        if heard.who == nil or Playing(heard.who) then
            count = count + 1
            itemID = itemID or heard.itemID
        end
    end
    if count == 0 then return end
    out[#out + 1] = {
        kind = "mail", key = "mail:" .. count, itemID = itemID,
        text = (count == 1 and L["1 sale is waiting in your mail"] or L.Format("%d sales are waiting in your mail", count)),
        button = L["Show Them"], action = "sales",
    }
end

function builders.undercut(out)
    local my = ns.MyAuctions
    if not (my and my.Rows) then return end
    local rows = Try(my.Rows, my)
    if type(rows) ~= "table" then return end
    local count, first = 0, nil
    for _, row in ipairs(rows) do
        if row.mine and row.state == "undercut" and not row.cancelling then
            count = count + 1
            first = first or row
        end
    end
    if count == 0 then return end
    local name, waiting = Today.ItemName(first.itemID, first.link)
    local detail = name
    if name and count > 1 then detail = name .. " " .. L.Format("and %d more", count - 1) end
    out[#out + 1] = {
        kind = "undercut", key = ("undercut:%d:%s:%s"):format(count, tostring(first.itemID), waiting and "?" or ""),
        itemID = first.itemID, link = first.link,
        text = (count == 1 and L["1 of your auctions was undercut"] or L.Format("%d of your auctions were undercut", count)),
        detail = detail,
        button = L["Show Them"], action = "auctions",
    }
end

local function ProfitEach(recipeID)
    local profit = ns.CraftProfit
    if not (profit and profit.For) then return nil end
    local figures = Try(profit.For, profit, recipeID)
    return type(figures) == "table" and figures.profit or nil
end

local function Queued(recipeID)
    local queue = ns.Queue
    if not (queue and queue.Find) then return false end
    local _, found = Try(queue.Find, queue, recipeID)
    return found ~= nil
end

function builders.ready(out)
    local cooldowns = ns.Cooldowns
    if not (cooldowns and cooldowns.ReadyList) then return end
    local list = Try(cooldowns.ReadyList, cooldowns)
    if type(list) ~= "table" then return end
    local shown = 0
    for _, entry in ipairs(list) do
        if shown >= Today.MOST_EACH then break end
        if Playing(entry.key) and entry.recipeID and not Queued(entry.recipeID) then
            local name, waiting = entry.name, false
            if entry.itemID then name, waiting = Today.ItemName(entry.itemID, entry.name) end
            if name then
                shown = shown + 1
                local each = ProfitEach(entry.recipeID)
                out[#out + 1] = {
                    kind = "ready", key = ("ready:%s:%s:%s"):format(entry.recipeID, tostring(each), waiting and "?" or ""),
                    itemID = entry.itemID, recipeID = entry.recipeID,
                    text = L.Format("%s is ready to make", name),
                    money = each, moneyFormat = L["%s each"], signed = true,
                    button = L["Queue It"], action = "queueOne",
                }
            end
        end
    end
end

function builders.soldout(out)
    local db, auctions, queue = ns.db, ns.Auctions, ns.Queue
    if not (type(db) == "table" and type(db.postLimits) == "table" and auctions and auctions.GetRoom
        and queue and queue.RecipeFor) then return end
    local found = {}
    for itemID, limit in pairs(db.postLimits) do
        if type(itemID) == "number" and (tonumber(limit) or 0) > 0 then
            local room, posted, onHand, queued, keep, inMail = Try(function()
                return auctions:GetRoom(itemID, nil, true)
            end)
            if room and room > 0 and (posted or 0) == 0 and (onHand or 0) == 0
                and (queued or 0) == 0 and (inMail or 0) == 0 then
                local recipeID, recipe = Try(queue.RecipeFor, queue, itemID)
                if recipeID then
                    found[#found + 1] = { itemID = itemID, recipeID = recipeID, recipe = recipe,
                        room = room, keep = keep or limit, each = ProfitEach(recipeID) }
                end
            end
        end
    end
    table.sort(found, function(a, b)
        local x, y = a.each or -math.huge, b.each or -math.huge
        if x ~= y then return x > y end
        return a.itemID < b.itemID
    end)
    for index = 1, math.min(#found, Today.MOST_EACH) do
        local item = found[index]
        local recipe = type(item.recipe) == "table" and item.recipe or {}
        local name, waiting = Today.ItemName(item.itemID, recipe.name)
        if name then
            out[#out + 1] = {
                kind = "soldout", key = ("soldout:%d:%d:%s:%s"):format(item.itemID, item.room, tostring(item.each), waiting and "?" or ""),
                itemID = item.itemID, recipeID = item.recipeID, recipe = item.recipe, room = item.room,
                text = L.Format("%s sold out. You keep %d listed.", name, item.keep),
                money = item.each, moneyFormat = L["%s each"], signed = true,
                button = L.Format("Queue %d", item.room), action = "queueRoom",
            }
        end
    end
end

--------------------------------------------------------------------------------
-- The Profit list, ranked a few recipes a frame
--------------------------------------------------------------------------------

local ranked     -- { key, count, best, itemID }
local ranking    -- the ranking under way

local function RankKey()
    local me = ns.Config and ns.Config.GetCharacterKey and Try(ns.Config.GetCharacterKey, ns.Config)
    local record = me and ns.db and ns.db.characters and ns.db.characters[me]
    return table.concat({
        tostring(me),
        tostring(record and record.recipesCachedAt or 0),
        tostring(ns.Prices and ns.Prices.scanCount or 0),
        tostring(ns.Queue and ns.Queue.version or 0),
        tostring(ns.Config and ns.Config.changes or 0),
    }, "|")
end

local function Summarise(results)
    local count, best, itemID = 0, nil, nil
    for _, analysis in ipairs(results or {}) do
        if analysis.priceable and (analysis.profit or 0) > 0 then
            count = count + 1
            if not best or analysis.profit > best then
                best, itemID = analysis.profit, analysis.outputItemID
            end
        end
    end
    return count, best, itemID
end

--- The Profit list's count and best profit, or nil while it is worked out.
--- onReady is called once a ranking that was not ready is done.
function Today:Ranked(onReady)
    local profit = ns.Profit
    if not (profit and profit.BeginRanked and profit.RankOne and profit.FinishRanked) then return nil end
    local key = RankKey()
    if ranked and ranked.key == key then return ranked end
    if ranking and ranking.key == key then
        ranking.onReady = onReady or ranking.onReady
        return nil
    end

    local begun = Try(profit.BeginRanked, profit, {})
    if type(begun) ~= "table" then return nil end
    local this = { key = key, onReady = onReady, index = 0, begun = begun }
    ranking = this

    local function Finish()
        ranking = nil
        local results = Try(profit.FinishRanked, profit, begun) or {}
        local count, best, itemID = Summarise(results)
        ranked = { key = key, count = count, best = best, itemID = itemID }
        return ranked
    end

    local after = rawget(_G, "C_Timer") and C_Timer.After
    if type(after) ~= "function" then
        for _, item in ipairs(begun.items) do Try(profit.RankOne, profit, begun, item) end
        return Finish()
    end

    local function Slice()
        if ranking ~= this then return end
        for _ = 1, Today.BUDGET do
            this.index = this.index + 1
            local item = begun.items[this.index]
            if not item then
                Finish()
                if this.onReady then pcall(this.onReady) end
                return
            end
            Try(profit.RankOne, profit, begun, item)
        end
        after(0, Slice)
    end
    after(0, Slice)
    return nil
end

--- Forget the kept ranking (tests, or a price the player changed).
function Today:Forget()
    ranked, ranking = nil, nil
end

function builders.profit(out, onReady)
    local result = Today:Ranked(onReady)
    if not (result and result.count > 0) then return end
    out[#out + 1] = {
        kind = "profit", key = ("profit:%d:%s"):format(result.count, tostring(result.best)),
        itemID = result.itemID,
        text = (result.count == 1 and L["1 craft pays well right now"] or L.Format("%d crafts pay well right now", result.count)),
        money = result.best, moneyFormat = L["best %s"], signed = true,
        button = L["Show Them"], action = "profit",
    }
end

function builders.writs(out)
    local writs = ns.Writs
    if not (writs and writs.GetRows) then return end
    local rows = Try(writs.GetRows, writs)
    if type(rows) ~= "table" then return end
    local count, gain, itemID = 0, 0, nil
    for _, row in ipairs(rows) do
        if row.total and row.total < 0 and not row.done and not row.noneListed then
            count = count + 1
            gain = gain - row.total
            itemID = itemID or row.itemID
        end
    end
    if count == 0 then return end
    out[#out + 1] = {
        kind = "writs", key = ("writs:%d:%d"):format(count, math.floor(gain)),
        itemID = itemID,
        text = (count == 1 and L["1 writ is worth doing today"] or L.Format("%d writs are worth doing today", count)),
        money = gain, signed = true,
        button = L["Show Writs"], action = "writs",
    }
end

--- The crafts and cost from the current step of a road plan to where a
--- new recipe takes over, or nil when the next step is not a craft.
function Today.NextStretch(plan)
    if type(plan) ~= "table" or not plan.current or type(plan.steps) ~= "table" then return nil end
    local first = plan.steps[plan.current]
    if not (first and first.kind == "craft" and first.recipeID) then return nil end
    local crafts, cost = 0, 0
    for index = plan.current, #plan.steps do
        local step = plan.steps[index]
        if step.kind ~= "craft" or step.recipeID ~= first.recipeID then break end
        crafts = crafts + (step.crafts or 0)
        cost = cost + (step.cost or 0)
    end
    if crafts <= 0 then return nil end
    return crafts, cost, first.outputItemID
end

function builders.road(out, onReady)
    local road = ns.RoadPlan
    if not (road and road.Professions and road.Get) then return end
    local professions = Try(road.Professions, road)
    if type(professions) ~= "table" then return end
    local shown = 0
    for _, profession in ipairs(professions) do
        if shown >= Today.MOST_EACH then break end
        local target = road.TARGET or 300
        if (profession.skill or 0) < target and profession.line ~= road.FISHING then
            local plan = Try(road.Get, road, profession, onReady)
            local crafts, cost, itemID = Today.NextStretch(plan)
            if crafts then
                shown = shown + 1
                out[#out + 1] = {
                    kind = "road",
                    key = ("road:%s:%d:%d:%d"):format(tostring(profession.line), profession.skill or 0,
                        crafts, math.floor(cost)),
                    itemID = itemID, line = profession.line,
                    text = L.Format("%s %d.", profession.name, profession.skill or 0) .. " "
                        .. (crafts == 1 and L["1 craft to your next recipe."] or L.Format("%d crafts to your next recipe.", crafts)),
                    money = cost, moneyFormat = L["costs %s"],
                    button = L["Open Road"], action = "road",
                }
            end
        end
    end
end

--- Every line to show, in order. onReady is called when a slow part (the
--- Profit ranking, a road plan) finishes, so the tab can draw again.
function Today:Lines(onReady)
    onNamed = onReady
    local out = {}
    for _, kind in ipairs(Today.KINDS) do
        if self:IsShown(kind) and builders[kind] then
            local ok, err = pcall(builders[kind], out, onReady)
            if not ok and ns.Debug then ns.Debug("today " .. kind .. ":", tostring(err)) end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- What a line's button does
--------------------------------------------------------------------------------

local function Say(why)
    if why and ns.Print then ns.Print(tostring(why)) end
end

--- @return true when it did what the button says
function Today:Run(line)
    if type(line) ~= "table" then return false end
    local UI = ns.UI
    local action = line.action

    if action == "queueOne" then
        local queue = ns.Queue
        if not (queue and queue.Ensure) then return false end
        local ok, done, why = pcall(queue.Ensure, queue, line.recipeID, 1)
        if ok and done then return true end
        Say(ok and why)
        return false
    elseif action == "queueRoom" then
        local queue, profit = ns.Queue, ns.Profit
        if not (queue and queue.Add) then return false end
        local crafts = profit and profit.RoomInCrafts and Try(profit.RoomInCrafts, line.room, line.recipe) or line.room
        local ok, done, why = pcall(queue.Add, queue, line.recipeID, math.max(1, tonumber(crafts) or 1))
        if ok and done then return true end
        Say(ok and why)
        return false
    elseif action == "sales" or action == "auctions" then
        if action == "auctions" and UI and UI.AtAuctionHouse and UI:AtAuctionHouse() and ns.PostPanel then
            if UI.tabs and UI.tabs.auctionhouse and UI.SelectTab then UI:SelectTab("auctionhouse") end
            Try(ns.PostPanel.SetView, ns.PostPanel, "auctions")
            return true
        end
        if not (UI and UI.SelectTab) then return false end
        UI:SelectTab("sales")
        if ns.SalesTab and ns.SalesTab.ShowView then
            ns.SalesTab.ShowView(action == "auctions" and "listed" or "sales")
        end
        return true
    elseif action == "profit" then
        if not (UI and UI.SelectTab) then return false end
        UI:SelectTab("profit")
        if ns.ProfitTab and ns.ProfitTab.ShowView then Try(ns.ProfitTab.ShowView, "crafts") end
        return true
    elseif action == "writs" then
        if not (UI and UI.SelectTab) then return false end
        UI:SelectTab("deals")
        if UI.DealsSetView then Try(UI.DealsSetView, "writs") end
        return true
    elseif action == "road" then
        if ns.LevelUpTab and ns.LevelUpTab.ShowRoad then
            Try(ns.LevelUpTab.ShowRoad, line.line)
            return true
        end
        return false
    end
    return false
end


