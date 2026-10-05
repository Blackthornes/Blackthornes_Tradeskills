-- Blackthornes Tradeskills -- UI/Tab_Queue.lua
-- Queued crafts on the left, the materials they need on the right.
--
-- These are one screen rather than two tabs on purpose: "what am I making" and
-- "what am I missing" are the same question, and splitting them means bouncing
-- between tabs to answer it.

local _, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local UI = ns.UI

local ROW_HEIGHT = 24
-- Wider since 2026-10-05, with the window: the headings sat tight against
-- each other and long material names were cut short. The craft list keeps
-- the width it had, because the window grew by the same amount.
local MATERIALS_WIDTH = 420

-- Right-aligned columns for the materials panel, laid out from the right edge
-- inward. The AH button occupies the rightmost slot. COST is wide enough for
-- all three coins ("12g 34s 56c"): at 48 the copper was cut off. NEED and
-- HAVE are wide enough for four digits, with a gap between every column.
local MATERIAL_COLUMNS = {
    { key = "cost", label = "COST", width = 70, offset = -36 },
    { key = "have", label = "HAVE", width = 42, offset = -114 },
    { key = "need", label = "NEED", width = 42, offset = -164 },
}

local MATERIAL_NAME_INSET = -214

-- The queued amount is a box you can type in (asked 2026-10-05: taking 100
-- off meant 100 clicks on -). Wide enough for four digits; the label it
-- replaced was 22 wide and lost the last digit of 100.
local QUANTITY_WIDTH = 42

local widgets = {}

-- Each queued craft's cost and profit for its whole count, worked out once
-- per redraw (Queue:GetEntryCosts) so a row and the footer agree.
local entryCosts = {}

--------------------------------------------------------------------------------
-- Craft rows
--------------------------------------------------------------------------------

local function CreateCraftRow(row)
    -- The item's icon beside its name, as the bags draw it.
    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 8, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 28, 0)
    -- Ends short of the profit column, so a long amount never draws over it.
    row.name:SetPoint("RIGHT", row, "RIGHT", -200, 0)

    row.profit = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.profit:SetPoint("RIGHT", -114, 0)
    row.profit:SetWidth(80)

    -- Quantity stepper: - and + either side of a box you can type the
    -- amount into. 0 takes the craft off the queue, as - does at 1.
    row.minus = Widgets.CreateButton(row, "-", function()
        if not row.data then return end
        ns.Queue:SetQuantity(row.data.recipeID, row.data.quantity - 1)
    end, { width = 18, height = 16 })
    row.minus:SetPoint("RIGHT", -90, 0)

    row.quantity = Widgets.CreateNumberBox(row, {
        width = QUANTITY_WIDTH,
        height = 18,
        background = "panel",
        justify = "CENTER",
        min = 0,
        max = 9999,
        onChange = function(value)
            if row.data then ns.Queue:SetQuantity(row.data.recipeID, value) end
        end,
    })
    row.quantity:SetPoint("RIGHT", -45, 0)

    -- Sub-crafts show their amount without the box: it comes from the
    -- crafts they serve, so a typed one would be worked out away again.
    row.count = Theme.CreateLabel(row, "small", "accent", "CENTER")
    row.count:SetPoint("RIGHT", -45, 0)
    row.count:SetWidth(QUANTITY_WIDTH)

    row.plus = Widgets.CreateButton(row, "+", function()
        if not row.data then return end
        ns.Queue:SetQuantity(row.data.recipeID, row.data.quantity + 1)
    end, { width = 18, height = 16 })
    row.plus:SetPoint("RIGHT", -24, 0)

    row.remove = Widgets.CreateButton(row, "x", function()
        if not row.data then return end
        ns.Queue:Remove(row.data.recipeID)
    end, { width = 16, height = 16, tooltip = "Remove from queue" })
    row.remove:SetPoint("RIGHT", -4, 0)

    -- On a sub-craft kept after buying its item turned cheaper, in the
    -- profit column, which such a row has no use for.
    row.buyInstead = Widgets.CreateButton(row, "Buy instead", function()
        if row.data then ns.Queue:BuyInstead(row.data) end
    end, { width = 80, height = 18 })
    row.buyInstead:SetPoint("RIGHT", -114, 0)
    row.buyInstead:Hide()
end

--- The hover for Buy instead: both prices, when known, and what it does.
local function BuyInsteadTooltip(entry)
    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local name = (recipe and recipe.name) or "this"
    local buy, make = ns.Queue:GetBuyOrMake(entry)

    local text = ("Buying %s is now cheaper than making it."):format(name)
    if buy and make then
        text = ("%s\nBuy: %s each. Make: %s each."):format(text,
            Util.FormatMoney(buy), Util.FormatMoney(make))
    end
    return text .. "\nBuy instead takes it off the queue and puts it on the shopping list."
end

local function UpdateCraftRow(row, entry)
    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local analysis = ns.Profit:Analyse(entry.recipeID)

    local plain = (recipe and recipe.name) or ("recipe " .. entry.recipeID)
    local label = plain
    Theme.SetItemIcon(row.icon, recipe and recipe.outputItemID)

    -- Marked so a craft the player did not add directly is explicable.
    if entry.isDependency then
        local parents = ns.Queue:GetDependencyParents(entry)

        label = ("|cff7a8089>|r %s |cff7a8089(for %s)|r"):format(
            plain,
            #parents > 0 and table.concat(parents, ", ") or "another craft")
    end

    -- Who it is for and who makes it, when that is not all this character:
    -- "you make this for Ana" on the tailor, "Bob makes this for you" on
    -- Ana. The longest wording that fits the row, then shorter ones.
    local who = ns.Queue.DescribeWho and ns.Queue:DescribeWho(entry) or {}
    local texts = {}
    local function Note(base, text)
        return ("%s |cff7a8089·|r |cffc8a44d%s|r"):format(base, text)
    end

    -- Kept after buying turned cheaper: said on the row ahead of who makes
    -- it, so it is not mistaken for the cheaper way.
    if entry.buyCheaper then
        local cheaper = ("|c%sbuying is cheaper now|r"):format(ns.COLORS.warn)
        texts[#texts + 1] = ("%s |cff7a8089·|r %s"):format(label, cheaper)
        texts[#texts + 1] = ("%s |cff7a8089·|r %s"):format(plain, cheaper)
    end
    for _, text in ipairs(who) do texts[#texts + 1] = Note(label, text) end
    if #who > 0 then texts[#texts + 1] = Note(plain, who[#who]) end
    texts[#texts + 1] = label
    texts[#texts + 1] = plain
    Theme.FitText(row.name, texts)

    -- Colour by whether it can be made, since nothing here can start one.
    local ready, reason = ns.Crafting:GetReadiness(entry.recipeID)
    local countColor = ready and "profit" or "muted"
    row.count:SetTextColor(Theme.Unpack(countColor))
    row.quantity.editBox:SetTextColor(Theme.Unpack(countColor))

    -- Derived rows have no controls: their quantity comes from the parents,
    -- so anything set here would be recalculated away on the next change.
    row.minus:SetShown(not entry.isDependency)
    row.plus:SetShown(not entry.isDependency)
    row.remove:SetShown(not entry.isDependency)
    row.quantity:SetShown(not entry.isDependency)
    row.count:SetShown(entry.isDependency == true)
    row.count:SetText(tostring(entry.quantity))

    -- A redraw leaves a number being typed alone, unless the row now shows
    -- a different craft: then what was typed belonged to the old one.
    local typing = row.quantity.editBox.HasFocus and row.quantity.editBox:HasFocus()
    if typing and row.boundRecipeID ~= entry.recipeID then
        row.quantity:SetValue(entry.quantity, true)
        row.quantity.editBox:ClearFocus()
    elseif not typing then
        row.quantity:SetValue(entry.quantity, true)
    end
    row.boundRecipeID = entry.recipeID

    local kept = entry.isDependency and entry.buyCheaper == true
    row.buyInstead:SetShown(kept)
    row.profit:SetShown(not kept)
    if kept then row.buyInstead.tooltipText = BuyInsteadTooltip(entry) end

    if entry.isDependency then
        -- Made to go into another craft, not sold, so it earns nothing of
        -- its own. The footer already counts it that way; a sale profit here
        -- made the column add up to more than the total under it.
        row.profit:SetText("used")
        row.profit:SetTextColor(Theme.Unpack("dim"))
        row.name:SetTextColor(Theme.Unpack("text"))
    elseif analysis and analysis.priceable then
        local priced = entryCosts[entry]
        local total = priced and priced.profit or (analysis.profit * entry.quantity)
        row.profit:SetText(Util.FormatMoney(total, { short = true }))
        row.profit:SetTextColor(Theme.ProfitColor(total))

        -- A craft queued when it was worth 4g and now worth 40s should say so,
        -- rather than silently re-pricing.
        if entry.snapshotProfit and entry.snapshotProfit > 0 then
            local drift = analysis.profit / entry.snapshotProfit
            if drift < 0.6 then
                row.name:SetTextColor(Theme.Unpack("warn"))
                return
            end
        end
        row.name:SetTextColor(Theme.Unpack("text"))
    else
        row.profit:SetText("--")
        row.profit:SetTextColor(Theme.Unpack("dim"))
        row.name:SetTextColor(Theme.Unpack("muted"))
    end
end

--------------------------------------------------------------------------------
-- Material rows
--------------------------------------------------------------------------------

local function CreateMaterialRow(row)
    row.icon = Theme.CreateItemIcon(row, 14)
    row.icon:SetPoint("LEFT", 6, 0)

    row.name = Theme.CreateLabel(row, "small", "text")
    row.name:SetPoint("LEFT", 24, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", MATERIAL_NAME_INSET, 0)

    row.cells = {}
    for _, column in ipairs(MATERIAL_COLUMNS) do
        local cell = Theme.CreateLabel(row, "small", "muted", "RIGHT")
        cell:SetPoint("RIGHT", column.offset, 0)
        cell:SetWidth(column.width)
        row.cells[column.key] = cell
    end

    row.search = Widgets.CreateButton(row, "AH", function()
        if row.data then UI:SearchAuctionHouse(row.data.itemID) end
    end, { width = 26, height = 16, tooltip = "Search the auction house for this" })
    row.search:SetPoint("RIGHT", -4, 0)
end

local function UpdateMaterialRow(row, line)
    -- The name in its item colour, unless it is recoloured below: a link's
    -- own colour shows over the label's, so a recoloured name goes without.
    local label = Util.GetItemLabel(line.itemID)
    local nameColour = line.shortfall <= 0 and "muted" or line.altCraft and "profit" or nil
    row.name:SetText(nameColour and Util.Uncolored(label) or label)
    Theme.SetItemIcon(row.icon, line.itemID)

    local cells = row.cells

    -- Need and have as separate columns under their own headings, rather than
    -- a combined "2/5" that has to be decoded. The raw holding is shown here,
    -- surplus and all, because the column heading now says what it means.
    cells.need:SetText(tostring(line.needed))
    cells.need:SetTextColor(Theme.Unpack("muted"))

    cells.have:SetText(tostring(line.have))

    if line.shortfall > 0 then
        cells.have:SetTextColor(Theme.Unpack("loss"))
    elseif line.needsBankTrip or line.needsMailTrip then
        -- Owned, but not on you. Amber rather than green: nothing to buy, but
        -- you cannot craft it until you visit the bank or the mailbox.
        cells.have:SetTextColor(Theme.Unpack("warn"))
    else
        cells.have:SetTextColor(Theme.Unpack("profit"))
    end

    if line.shortfall > 0 then
        -- Measured: an amount too wide for the column loses coins, rounded,
        -- rather than ending in "...".
        if line.estimatedCost then
            Theme.SetMoneyText(cells.cost, line.estimatedCost, { short = true })
        else
            cells.cost:SetText("?")
        end
        cells.cost:SetTextColor(Theme.Unpack(line.fromVendor and "accent" or "muted"))

        -- Green: another of your characters can make it for less.
        row.name:SetTextColor(Theme.Unpack(nameColour or "text"))

        -- Buying a vendor reagent off the auction house is a mistake, so do
        -- not offer the search for it.
        row.search:SetShown(not line.fromVendor)
    else
        cells.cost:SetText(line.needsBankTrip and "in bank"
            or line.needsMailTrip and "in mail" or "")
        cells.cost:SetTextColor(Theme.Unpack("warn"))

        row.name:SetTextColor(Theme.Unpack(nameColour))
        row.search:Hide()
    end
end

--- Full numbers on hover, including surplus and anything held by alts.
-- On UI as well, for the shopping list beside the profession window.
local function ShowMaterialTooltip(row, line)
    ns.Widgets.ShowItemTooltip(row, "ANCHOR_RIGHT", line.itemID, Util.GetItemLabel(line.itemID))
    GameTooltip:AddLine(" ")

    if line.fromVendor then
        GameTooltip:AddLine(line.vendorLimited
            and "Sold by a vendor (limited stock)" or "Sold by a vendor", 0.78, 0.64, 0.30)
    end

    GameTooltip:AddDoubleLine("Required", tostring(line.needed), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("In bags", tostring(line.inBags or 0), 0.7, 0.7, 0.7, 1, 1, 1)

    if (line.inBank or 0) > 0 then
        GameTooltip:AddDoubleLine("In bank", tostring(line.inBank),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    if (line.inMail or 0) > 0 then
        GameTooltip:AddDoubleLine("In mail", tostring(line.inMail),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    if line.needsBankTrip then
        GameTooltip:AddLine("You own enough, but some is in the bank.", 0.91, 0.76, 0.35)
    elseif line.needsMailTrip then
        GameTooltip:AddLine("You own enough, but some is in the mailbox.", 0.91, 0.76, 0.35)
    end

    if line.have > line.needed then
        GameTooltip:AddDoubleLine("Surplus", tostring(line.have - line.needed),
            0.7, 0.7, 0.7, 0.31, 0.82, 0.55)
    end

    if line.shortfall > 0 then
        GameTooltip:AddDoubleLine("Still needed", tostring(line.shortfall),
            0.7, 0.7, 0.7, 0.9, 0.38, 0.31)

        if line.unitCost then
            GameTooltip:AddDoubleLine("Cost to buy",
                Util.FormatMoney(line.estimatedCost, { noColor = true }),
                0.7, 0.7, 0.7, 1, 1, 1)
        else
            GameTooltip:AddLine("No auction data for this material", 0.9, 0.38, 0.31)
        end
    end

    local offer = line.altCraft
    if offer then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Cheaper to make on %s"):format(offer.characterName), 0.31, 0.82, 0.55)
        GameTooltip:AddDoubleLine("Cost to make",
            Util.FormatMoney(offer.unitCost * line.shortfall, { noColor = true }),
            0.7, 0.7, 0.7, 1, 1, 1)
        if offer.saving then
            GameTooltip:AddDoubleLine("You save",
                Util.FormatMoney(offer.saving, { noColor = true }),
                0.7, 0.7, 0.7, 0.31, 0.82, 0.55)
        end
        GameTooltip:AddLine(("Log in on that character and %d x %s is queued there, with its materials to buy. Mail it across once made.")
            :format(offer.crafts, offer.recipeName or "it"), 0.7, 0.7, 0.7, true)
    end

    -- Shared with the alts: how much of this another character's crafts
    -- use. What they already hold of it is not on your list.
    if line.forOthers then
        local keys = {}
        for characterKey in pairs(line.forOthers) do keys[#keys + 1] = characterKey end
        table.sort(keys)
        for _, characterKey in ipairs(keys) do
            GameTooltip:AddDoubleLine(("For %s's crafts"):format(ns.Recipes:GetCharacterName(characterKey)),
                tostring(line.forOthers[characterKey]), 0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
        end
        if (line.othersHold or 0) > 0 then
            GameTooltip:AddDoubleLine("They already hold", tostring(line.othersHold),
                0.7, 0.7, 0.7, 0.31, 0.82, 0.55)
        end
    end

    -- Alt-held stock is never counted as yours automatically: it is not in
    -- reach of the craft you are about to make.
    if line.onAlts and line.onAlts > 0 then
        GameTooltip:AddDoubleLine("On other characters", tostring(line.onAlts),
            0.7, 0.7, 0.7, 0.91, 0.76, 0.35)
    end

    GameTooltip:Show()
end

UI.ShowMaterialTooltip = ShowMaterialTooltip

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

--- Warn when bank counts have not been refreshed this session.
local function UpdateBankNote()
    local note = widgets.bankNote
    if not note then return end

    -- Nothing queued means nothing to be wrong about; do not nag.
    if ns.Inventory:HasReadBankThisSession() or ns.Queue:Count() == 0 then
        note:SetText("")
        return
    end

    local age = ns.Inventory:GetBankAge()

    if age then
        note:SetText(("Bank not checked this session, so using what it held %s.")
            :format(Util.FormatAgeAgo(age)))
    else
        note:SetText("Bank never checked, so HAVE counts bags only.")
    end
end

--- Keep the Craft button honest about what it will do, and why it cannot.
-- @return true when the button was set to open a profession window
local function SetCraftButton(button, label)
    button.opensProfession = false

    if ns.Crafting:IsBusy() then
        button:SetText("Stop crafting")
        button:SetEnabledState(true)
        button.tooltipText = "Stop after the current craft"
        label:SetText("crafting...")
        label:SetTextColor(Theme.Unpack("profit"))
        return
    end

    if ns.Queue:Count() == 0 then
        button:SetText("Craft next")
        button:SetEnabledState(false)
        button.tooltipText = "Nothing is queued"
        label:SetText("")
        return
    end

    local ready, total = ns.Crafting:GetQueueReadiness()
    local entry = ns.Crafting:GetNextReady()

    if not entry then
        button:SetText("Craft next")
        button:SetEnabledState(false)

        -- Report the first entry's actual obstacle rather than a generic one.
        local _, reason = ns.Crafting:GetReadiness(ns.Queue:GetAll()[1].recipeID)

        button.tooltipText = reason or "Nothing here can be made yet"
        label:SetText(reason or "nothing ready")
        label:SetTextColor(Theme.Unpack("warn"))
        return
    end

    local recipe = ns.Recipes:GetAny(entry.recipeID)
    local canMake = math.min(entry.quantity, ns.Profit:GetCraftableCount(entry.recipeID))

    -- A craft only starts from its own profession window. When that is not
    -- the one open, this click opens it instead: the game lets a player's
    -- click cast the profession, which addon code alone may not do.
    local opener = ns.ProfessionOpener
    if opener and not opener:WindowShowsRecipe(entry.recipeID) then
        local profession = opener:ProfessionFor(entry.recipeID)

        if profession then
            button:SetText(("Open %s"):format(profession.name))
            button:SetEnabledState(true)
            button.tooltipText = ("Opens your %s window. Click again to craft %dx %s.")
                :format(profession.name, canMake, (recipe and recipe.name) or "item")

            label:SetText(("%d of %d ready. Click to open %s"):format(ready, total, profession.name))
            label:SetTextColor(Theme.Unpack("accent"))

            button.opensProfession = true
            opener:Arm(button, profession, entry.recipeID)
            return true
        end
    end

    button:SetText(("Craft %dx %s"):format(canMake, (recipe and recipe.name) or "item"))
    button:SetEnabledState(true)
    button.tooltipText = "One click makes every craft in this entry"

    label:SetText(("%d of %d ready"):format(ready, total))
    label:SetTextColor(Theme.Unpack("profit"))

    -- Crafting works without the window open on some clients and not others;
    -- say so rather than letting a click quietly do nothing.
    if not ns.Crafting.isTradeSkillOpen then
        label:SetText(("%d of %d ready. Open your profession"):format(ready, total))
        label:SetTextColor(Theme.Unpack("accent"))
    end
end

local function UpdateCraftStatus()
    local button, label = widgets.craftButton, widgets.craftStatus
    if not button then return end

    -- Every other state wants the click to reach the craft button itself.
    -- Only our own button, as the Level Up tab does: that tab may be holding
    -- the secure button over its Craft button.
    local opener = ns.ProfessionOpener
    if not SetCraftButton(button, label) and opener and opener.anchor == button then
        opener:Disarm()
    end
end

-- Suggestions already announced in chat this session, so each is said once.
local announcedAltCrafts = {}

--- Say in chat, once, each time a new cheaper way turns up on another character.
local function AnnounceAltCrafts(lines)
    local found = false

    for _, line in ipairs(lines) do
        local offer = line.altCraft
        local key = offer and (line.itemID .. ":" .. offer.characterKey)

        if key and not announcedAltCrafts[key] then
            announcedAltCrafts[key] = true
            found = true

            ns.Print(("Cheaper way found: %s can make %s%s. Log in there and it will be in your queue.")
                :format(offer.characterName, Util.GetItemLabel(line.itemID),
                    offer.saving and offer.saving > 0
                        and (" and save you %s"):format(Util.FormatMoney(offer.saving))
                        or ""))
        end
    end

    -- Settings: SOUNDS, Cheaper on another character.
    if found and type(PlaySound) == "function" and ns.Config:Get("altCraftSound") ~= false then
        local kits = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT or {}
        local kit = kits.LOOT_WINDOW_COIN_SOUND or 120
        pcall(PlaySound, kit)
    end
end

--- The line under the materials naming each character worth swapping to.
local MAX_ALT_NOTES = 3

local function UpdateAltNote(lines)
    local note = widgets.altNote
    if not note then return end

    local notes, extra = {}, 0
    for _, line in ipairs(lines) do
        local offer = line.altCraft
        if offer then
            if #notes < MAX_ALT_NOTES then
                notes[#notes + 1] = ("Swap to %s to make %s%s"):format(
                    offer.characterName, Util.GetItemLabel(line.itemID),
                    offer.saving and offer.saving > 0
                        and (", saves %s"):format(Util.FormatMoney(offer.saving, { short = true }))
                        or "")
            else
                extra = extra + 1
            end
        end
    end

    if extra > 0 then
        notes[#notes + 1] = ("and %d more, shown in green"):format(extra)
    end

    note:SetText(table.concat(notes, "\n"))

    -- The list makes room for the note rather than running under it.
    local reserve = 48
    if #notes > 0 then
        reserve = reserve + (note:GetStringHeight() or 0) + 4
    end
    widgets.materialList:SetPoint("BOTTOMRIGHT", widgets.materials, "BOTTOMRIGHT", -10, reserve)
end

local function Refresh()
    if not widgets.craftList then return end

    local queue = ns.Queue:GetAll()

    -- Copy so sorting for display never reorders the stored queue.
    local entries = {}
    for index, entry in ipairs(queue) do
        entries[index] = entry
    end

    entryCosts = ns.Queue:GetEntryCosts()
    widgets.craftList:SetData(entries)
    local shopping = ns.Queue:GetShoppingList()
    -- A clicked heading's order over the list's own.
    widgets.materialList:SetData(widgets.materialSorter and widgets.materialSorter:Sort(shopping) or shopping)
    UpdateAltNote(shopping)
    AnnounceAltCrafts(shopping)

    widgets.emptyLabel:SetShown(#entries == 0)

    local totals = ns.Queue:GetTotals()
    -- From the list already built above, not a second walk of everything.
    local shoppingCost, unknown = ns.Queue:GetShoppingTotal(shopping)

    UpdateCraftStatus()
    UpdateBankNote()

    if #entries == 0 then
        widgets.summaryLabel:SetText("")
        widgets.shoppingLabel:SetText("")
        return
    end

    widgets.summaryLabel:SetText(("%d craft%s  ·  materials %s  ·  profit %s%s"):format(
        totals.crafts, totals.crafts == 1 and "" or "s",
        Util.FormatMoney(totals.cost, { short = true }),
        Util.FormatMoney(totals.profit, { short = true }),
        totals.priceable and "" or "  (some unpriced)"))

    widgets.shoppingLabel:SetText(("To buy: %s%s"):format(
        Util.FormatMoney(shoppingCost, { short = true }),
        unknown > 0 and ("  (+%d unpriced)"):format(unknown) or ""))
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function Build(container)
    local heading = Theme.CreateLabel(container, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 8, -10)
    heading:SetText("QUEUED CRAFTS")

    -- A queue can take a while to build, so emptying it takes a second click,
    -- the same as Clear queue on the craft pane.
    local clear
    local armedUntil

    local function Disarm()
        armedUntil = nil
        clear:SetText("Clear all")
        clear:SetConfirming(false)
        clear.tooltipText = "Empty the whole craft queue. Asks you to click again first."
    end

    clear = Widgets.CreateButton(container, "Clear all", function()
        if armedUntil and GetTime() < armedUntil then
            local count = ns.Queue:Count()
            Disarm()
            ns.Queue:Clear()
            ns.Print(("Craft queue cleared (%d entr%s)."):format(count, count == 1 and "y" or "ies"))
            return
        end

        if ns.Queue:Count() == 0 then return end

        armedUntil = GetTime() + 4
        clear:SetText("Really clear?")
        clear:SetConfirming(true)
        clear.tooltipText = "Click again to empty the whole craft queue"

        C_Timer.After(4, function()
            if armedUntil and GetTime() >= armedUntil then Disarm() end
        end)
    end, { width = 84, height = 18 })
    clear.tooltipText = "Empty the whole craft queue. Asks you to click again first."
    clear:SetPoint("TOPRIGHT", container, "TOPRIGHT", -MATERIALS_WIDTH - 16, -8)

    local divider = Theme.CreateDivider(container)
    divider:SetPoint("TOPLEFT", 8, -26)
    divider:SetPoint("TOPRIGHT", container, "TOPRIGHT", -MATERIALS_WIDTH - 16, -26)
    -- Kept as the list's anchor, but the heading carries the house rule now,
    -- running from the words to the Clear all button, like MATERIALS NEEDED.
    divider:Hide()
    Theme.StyleHeading(heading, container)
    heading.rule:ClearAllPoints()
    heading.rule:SetPoint("LEFT", heading, "RIGHT", 6, 0)
    heading.rule:SetPoint("RIGHT", clear, "LEFT", -8, 0)

    local craftList = Widgets.CreateScrollList(container, {
        -- The craft being made stays lit, as in the craft pane's list.
        isSelected = function(entry)
            local active = ns.Crafting.active
            return active ~= nil and active.recipeID == entry.recipeID
        end,
        rowHeight = ROW_HEIGHT,
        createRow = CreateCraftRow,
        updateRow = UpdateCraftRow,

        -- The item the craft makes, as the bags would show it.
        onEnter = function(row, entry)
            local recipe = ns.Recipes:GetAny(entry.recipeID)
            Widgets.ShowItemOnly(row, recipe and recipe.outputItemID, recipe and recipe.name)
        end,
        onLeave = function() GameTooltip:Hide() end,
    })
    craftList:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -4)
    craftList:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -MATERIALS_WIDTH - 16, 62)
    widgets.craftList = craftList

    -- Crafting needs a hardware event, so this is a real click each time:
    -- one click runs one queue entry to completion.
    widgets.craftButton = Widgets.CreateButton(container, "Craft next", function()
        if ns.Crafting:IsBusy() then
            ns.Crafting:Stop()
        else
            local entry = ns.Crafting:GetNextReady()
            if widgets.craftButton.opensProfession and ns.ProfessionOpener then
                -- The secure Open button should have taken this click.
                ns.ProfessionOpener:MissedClick()
            elseif entry then
                ns.Crafting:Start(entry.recipeID, entry.quantity)
            end
        end

        Refresh()
    end, { width = 220, height = 26, primary = true })
    widgets.craftButton:SetPoint("BOTTOMLEFT", 8, 32)

    widgets.craftStatus = Theme.CreateLabel(container, "small", "accent")
    widgets.craftStatus:SetPoint("LEFT", widgets.craftButton, "RIGHT", 10, 0)
    widgets.craftStatus:SetWidth(320)

    -- While a craft casts, a progress bar takes the status line's place.
    widgets.craftProgress = ns.CraftProgress:Create(container, {
        width = 320, height = 20, covers = widgets.craftStatus,
    })
    widgets.craftProgress:SetPoint("LEFT", widgets.craftButton, "RIGHT", 10, 0)


    local emptyLabel = Theme.CreateLabel(container, "small", "dim", "CENTER")
    emptyLabel:SetPoint("CENTER", craftList, "CENTER")
    emptyLabel:SetWidth(300)
    emptyLabel:SetWordWrap(true)
    emptyLabel:SetText("Nothing queued.\nRight-click a craft on the Profit tab to add one.")
    widgets.emptyLabel = emptyLabel

    local summaryLabel = Theme.CreateLabel(container, "small", "text")
    summaryLabel:SetPoint("BOTTOMLEFT", 8, 10)
    widgets.summaryLabel = summaryLabel

    -- Materials panel
    local materials = Theme.CreatePanel(container, "window")
    materials:SetPoint("TOPRIGHT", -8, -8)
    materials:SetPoint("BOTTOMRIGHT", -8, 8)
    materials:SetWidth(MATERIALS_WIDTH)
    widgets.materials = materials

    local materialsHeading = Theme.CreateLabel(materials, "tiny", "accent")
    materialsHeading:SetPoint("TOPLEFT", 10, -10)
    materialsHeading:SetText("MATERIALS NEEDED")
    -- The house heading: gold, with the rule running off to the right.
    Theme.StyleHeading(materialsHeading, materials)

    -- Column headings, so NEED and HAVE are labelled rather than inferred.
    local columnHeader = CreateFrame("Frame", nil, materials)
    columnHeader:SetPoint("TOPLEFT", 10, -28)
    columnHeader:SetPoint("TOPRIGHT", -10, -28)
    columnHeader:SetHeight(14)

    local nameHeading = Theme.CreateLabel(columnHeader, "tiny", "muted")
    nameHeading:SetPoint("LEFT", 24, 0)
    nameHeading:SetText("MATERIAL")

    local sortLabels = { name = nameHeading }
    for _, column in ipairs(MATERIAL_COLUMNS) do
        local heading = Theme.CreateLabel(columnHeader, "tiny", "muted", "RIGHT")
        heading:SetPoint("RIGHT", column.offset, 0)
        heading:SetWidth(column.width)
        heading:SetText(column.label)
        sortLabels[column.key] = heading
    end

    -- Click a heading to sort the materials by it.
    widgets.materialSorter = Widgets.SortableHeadings and Widgets.SortableHeadings(sortLabels, {
        name = function(line)
            local label = Util.GetItemLabel(line.itemID) or ""
            return label:match("%[(.-)%]") or label
        end,
        cost = function(line) return line.estimatedCost end,
        have = function(line) return line.have end,
        need = function(line) return line.needed end,
    }, function() Refresh() end)
    if widgets.materialSorter then widgets.materialSorter:SetText({ "name" }) end

    local materialsDivider = Theme.CreateDivider(materials)
    materialsDivider:SetPoint("TOPLEFT", 10, -45)
    materialsDivider:SetPoint("TOPRIGHT", -10, -45)

    local materialList = Widgets.CreateScrollList(materials, {
        rowHeight = 20,
        createRow = CreateMaterialRow,
        updateRow = UpdateMaterialRow,
        onEnter = ShowMaterialTooltip,
        onLeave = function() GameTooltip:Hide() end,
        -- The headings move in with the rows when the scrollbar takes its room.
        onScrollbarShown = function(shown)
            columnHeader:SetPoint("TOPRIGHT", shown and -20 or -10, -28)
        end,
    })
    materialList:SetPoint("TOPLEFT", materialsDivider, "BOTTOMLEFT", 0, -4)
    materialList:SetPoint("BOTTOMRIGHT", materials, "BOTTOMRIGHT", -10, 48)
    widgets.materialList = materialList

    -- Bank stock counts toward HAVE, so if the bank has not been opened this
    -- session those numbers may be understated. Say so rather than letting
    -- the player trust a stale snapshot.
    local bankNote = Theme.CreateLabel(materials, "tiny", "warn")
    bankNote:SetPoint("BOTTOMLEFT", 10, 26)
    bankNote:SetPoint("BOTTOMRIGHT", -10, 26)
    bankNote:SetWordWrap(true)
    bankNote:SetJustifyV("BOTTOM")
    widgets.bankNote = bankNote

    -- Materials another character can make for less, when Settings asks.
    -- Grows upward from just above the bank note.
    local altNote = Theme.CreateLabel(materials, "tiny", "profit")
    altNote:SetPoint("BOTTOMLEFT", 10, 48)
    altNote:SetPoint("BOTTOMRIGHT", -10, 48)
    altNote:SetWordWrap(true)
    altNote:SetJustifyV("BOTTOM")
    widgets.altNote = altNote

    local shoppingLabel = Theme.CreateLabel(materials, "small", "text")
    shoppingLabel:SetPoint("BOTTOMLEFT", 10, 10)
    widgets.shoppingLabel = shoppingLabel
end

UI:RegisterTab({
    key = "queue",
    text = "Queue",
    order = 2,
    build = Build,
    refresh = Refresh,
})

function UI:OnQueueUpdated()
    -- The craft pane beside the profession window shows the same queue, and
    -- is usually the thing that just changed it.
    if ns.CraftPanel then ns.CraftPanel:OnQueueChanged() end

    -- Only while the window is showing: redrawing a hidden Queue tab also
    -- ran its alt-craft announcement, chat line and coin sound included,
    -- every time something was queued from the craft pane.
    if self.activeTab == "queue" and self.window and self.window:IsShown() then
        Refresh()
    else
        -- The Gather tab is derived from the queue, so it goes stale too.
        self:RefreshActiveTab()
    end
end
