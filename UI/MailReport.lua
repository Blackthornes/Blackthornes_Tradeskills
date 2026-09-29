-- Blackthornes Tradeskills -- UI/MailReport.lua
-- The report after a mailbox visit, and the running tally while you are there.
--
-- Trent, 2026-09-28: "better mail tracking and reporting after mails are
-- collected, needs to look nextgen and keep with the dopamine hits as we're
-- doing with farmer". So collecting mail is a moment: a tally over the
-- mailbox counts up with a "+3g" rising off it each time gold lands, and when
-- you walk away a report opens with the total counting up to the sound of
-- coins, where it came from, the best sale lit gold, what came back, and a
-- fanfare when the visit beats your best haul or holds your best sale ever.
--
-- Logic/MailHaul.lua works out what was collected; this only draws it.

local ADDON, ns = ...

local Theme = ns.Theme
local Widgets = ns.Widgets
local Util = ns.Util

local MailReport = {}
ns.MailReport = MailReport

local WIDTH = 380
local PAD = 16
local ROW = 20
local MAX_SALE_ROWS = 5

local BRIGHT_GOLD = { 1, 0.84, 0.32 }

-- The addon's own sounds, made by tools/make_sounds.py. A file added since
-- the game started is only found after a full restart; until then the
-- game's own sounds play instead.
local MEDIA = ([[Interface\AddOns\%s\Media\Sounds\]]):format(ADDON)
MailReport.SOUNDS = {
    haul = MEDIA .. "mail-haul.ogg",
    record = MEDIA .. "mail-record.ogg",
}

-- The game's own, by id, for when the files cannot play: coins from the loot
-- window, then the achievement toast and the level-up chime.
local FALLBACK = {
    haul = { 120, 878 },
    record = { 12891, 888 },
}

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

--- Play one of the report's sounds. True if the game said it would.
function MailReport.Play(which)
    if type(PlaySoundFile) == "function" then
        local ok, willPlay = pcall(PlaySoundFile, MailReport.SOUNDS[which], "Master")
        if ok and willPlay then return true end
    end

    if type(PlaySound) == "function" then
        for _, id in ipairs(FALLBACK[which] or {}) do
            local ok, willPlay = pcall(PlaySound, id, "Master")
            if ok and willPlay then return true end
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Motion
--------------------------------------------------------------------------------

local effects = {}
local driver

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

local function Step(elapsed)
    local live = {}

    for _, effect in ipairs(effects) do
        effect.age = effect.age + (tonumber(elapsed) or 0)

        if effect.age < 0 then
            live[#live + 1] = effect
        else
            local p = math.min(1, effect.age / effect.duration)
            local ok, err = pcall(effect.apply, p)

            if not ok then
                ns.Debug("mail report effect dropped:", tostring(err))
                if effect.stop then pcall(effect.stop) end
            elseif p < 1 or effect.loop then
                if p >= 1 then effect.age = 0 end
                live[#live + 1] = effect
            end
        end
    end

    effects = live
    if #live == 0 and driver then driver:Hide() end
end

--- Start an effect: { slot, duration, delay, apply(p), stop(), loop }. A new
--- one in the same slot replaces the old.
function MailReport.Start(effect)
    for index = #effects, 1, -1 do
        if effect.slot and effects[index].slot == effect.slot then
            local old = table.remove(effects, index)
            if old.stop then pcall(old.stop) end
        end
    end

    effect.age = -(effect.delay or 0)
    effects[#effects + 1] = effect

    if not driver then
        driver = CreateFrame("Frame", nil, UIParent)
        driver:SetScript("OnUpdate", function(_, elapsed) Step(elapsed) end)
    end
    driver:Show()
end

--- Stop every effect whose slot starts with `prefix`, putting things back.
local function StopAll(prefix)
    local live = {}
    for _, effect in ipairs(effects) do
        if type(effect.slot) == "string" and effect.slot:sub(1, #prefix) == prefix then
            if effect.stop then pcall(effect.stop) end
        else
            live[#live + 1] = effect
        end
    end
    effects = live
end

--- A gold count running from `from` to `to` on `label`.
local function CountUp(slot, label, from, to, duration, delay, onDone)
    MailReport.Start({ slot = slot, duration = duration, delay = delay,
        apply = function(p)
            label:SetText(Util.FormatMoney(math.floor(from + (to - from) * EaseOut(p))))
            if p >= 1 and onDone then onDone() end
        end,
        stop = function() label:SetText(Util.FormatMoney(to)) end })
end

--- A label growing for a beat and settling back.
local function Pop(slot, label, size, delay)
    MailReport.Start({ slot = slot, duration = 0.35, delay = delay,
        apply = function(p)
            local grow = math.sin(p * math.pi) * 0.25
            pcall(label.SetFont, label, Theme.FONT, math.floor(size * (1 + grow) + 0.5), "OUTLINE")
        end,
        stop = function() pcall(label.SetFont, label, Theme.FONT, size, "OUTLINE") end })
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

local function Plural(n, one, many)
    return ("%d %s"):format(n, n == 1 and one or (many or one .. "s"))
end

--- "from 7 sales, 2 refunded bids and 1 letter"
function MailReport.Sources(haul)
    local parts = {}

    if (haul.salesCount or 0) > 0 then parts[#parts + 1] = Plural(haul.salesCount, "sale") end

    if (haul.gold and haul.gold.outbid or 0) > 0 then parts[#parts + 1] = "refunded bids" end

    if (haul.letters or 0) > 0 then parts[#parts + 1] = Plural(haul.letters, "letter") end

    if #parts == 0 then
        if (haul.itemCount or 0) > 0 then
            return ("%s collected"):format(Plural(haul.itemCount, "item"))
        end
        return ""
    end

    if #parts == 1 then return "from " .. parts[1] end
    local last = table.remove(parts)
    return ("from %s and %s"):format(table.concat(parts, ", "), last)
end

--- An item's name for the report, coloured by rarity where the game knows it.
local function ItemText(itemID, fallback)
    if not itemID then return fallback or "an item" end

    -- GetItemLabel says "item 1234" for an item the client has not cached,
    -- which a sold item usually is. The name the mail carried reads better.
    local label = Util.GetItemLabel(itemID)
    if type(label) == "string" and label ~= "" and not (fallback and label == ("item %d"):format(itemID)) then
        return label
    end

    return fallback or ("item " .. itemID)
end

--- "Linen Cloth x20, Wool Cloth x4 and 2 more"
local function ItemsLine(list)
    local parts = {}
    for index = 1, math.min(2, #list) do
        local entry = list[index]
        parts[#parts + 1] = ("%s x%d"):format(ItemText(entry.itemID), entry.count)
    end
    if #list > 2 then parts[#parts + 1] = ("%d more"):format(#list - 2) end
    return table.concat(parts, ", ")
end

local function Total(list)
    local n = 0
    for _, entry in ipairs(list or {}) do n = n + (entry.count or 0) end
    return n
end

--- The rows the report shows, top to bottom. Kept apart from the drawing so
--- the tests can read what the report says without a game client.
-- @return array of { type = "heading"|"money"|"sale"|"items", ... }
function MailReport.Lines(haul)
    local lines = {}
    local function Add(line) lines[#lines + 1] = line end

    local gold = haul.gold or {}
    local total = math.max(1, haul.total or 0)

    local sources = {
        { "Auction sales", gold.sold or 0, "profit" },
        { "Refunded bids", gold.outbid or 0, "accent" },
        { "Other mail", gold.other or 0, "text" },
    }

    local shown = 0
    for _, source in ipairs(sources) do
        if source[2] > 0 then shown = shown + 1 end
    end

    if shown > 0 then
        Add({ type = "heading", text = "WHERE IT CAME FROM" })
        for _, source in ipairs(sources) do
            if source[2] > 0 then
                Add({ type = "money", label = source[1], amount = source[2],
                    share = source[2] / total, color = source[3] })
            end
        end
    end

    local sales = haul.sales or {}
    if #sales > 0 then
        Add({ type = "heading", text = "BEST SALE" })
        Add({ type = "sale", itemID = sales[1].itemID, name = sales[1].name,
            amount = sales[1].amount, best = true, record = haul.recordSale })

        if #sales > 1 then
            Add({ type = "heading", text = "ALSO SOLD" })
            for index = 2, math.min(#sales, MAX_SALE_ROWS + 1) do
                local sale = sales[index]
                Add({ type = "sale", itemID = sale.itemID, name = sale.name, amount = sale.amount })
            end

            local more = (haul.salesCount or #sales) - math.min(#sales, MAX_SALE_ROWS + 1)
            if more > 0 then
                Add({ type = "items", label = ("and %s"):format(Plural(more, "more sale")), text = "", color = "muted" })
            end
        end
    end

    local items = haul.items or {}
    local kinds = {
        { "expired", "Came back unsold", "loss" },
        { "removed", "You cancelled", "muted" },
        { "won", "Bought", "profit" },
        { "other", "Items from letters", "text" },
    }

    local any = false
    for _, kind in ipairs(kinds) do
        if items[kind[1]] and #items[kind[1]] > 0 then any = true end
    end

    if any then
        Add({ type = "heading", text = "ITEMS COLLECTED" })
        for _, kind in ipairs(kinds) do
            local list = items[kind[1]]
            if list and #list > 0 then
                Add({ type = "items", label = ("%s (%d)"):format(kind[2], Total(list)),
                    text = ItemsLine(list), color = kind[3] })
            end
        end

        if (haul.returnedValue or 0) > 0 then
            Add({ type = "items", label = "Worth relisting",
                text = Util.FormatMoney(haul.returnedValue, { short = true }), color = "muted" })
        end
    end

    return lines
end

--------------------------------------------------------------------------------
-- The report window
--------------------------------------------------------------------------------

local function Bright(label)
    label:SetTextColor(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
end

local function Wash(parent, layer)
    local wash = parent:CreateTexture(nil, layer or "BACKGROUND", nil, 1)
    wash:SetAllPoints(parent)
    wash:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(wash.SetBlendMode, wash, "ADD")
    wash:SetAlpha(0)
    return wash
end

local SPARKS = {
    { 0.06, 0.25 }, { 0.14, 0.8 }, { 0.26, 0.1 }, { 0.38, 0.9 }, { 0.62, 0.12 },
    { 0.74, 0.85 }, { 0.86, 0.2 }, { 0.94, 0.7 }, { 0.5, 0.95 }, { 0.2, 0.5 },
}

function MailReport:Build()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "BlackthornesTSMailReport", UIParent)
    frame:SetSize(WIDTH, 300)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing() end)
    frame:SetScript("OnHide", function() StopAll("report") end)
    frame:Hide()

    Theme.Fill(frame, "window", 0.97)
    Theme.AddGameOutline(frame, { style = "dialog", color = "natural" })

    -- Escape closes it, like the main window.
    tinsert(UISpecialFrames, "BlackthornesTSMailReport")

    -- Header band: gold stripe, sheen, and a shine that sweeps it on open.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 6, -6)
    header:SetPoint("TOPRIGHT", -6, -6)
    header:SetHeight(34)
    Theme.Fill(header, "header")
    Theme.AccentStripe(header, 3)
    Theme.TopSheen(header, 0.08)
    frame.header = header

    local title = Theme.CreateLabel(header, "large", "accent")
    pcall(title.SetFont, title, Theme.FONT, Theme.sizes.large, "OUTLINE")
    Bright(title)
    title:SetPoint("LEFT", 14, 0)
    title:SetText("MAIL COLLECTED")
    frame.title = title

    local close = Widgets.CreateButton(header, "X", function() frame:Hide() end,
        { width = 22, height = 20, tooltip = "Close (Escape)" })
    close:SetPoint("RIGHT", -6, 0)

    local who = Theme.CreateLabel(header, "tiny", "muted", "RIGHT")
    who:SetPoint("RIGHT", close, "LEFT", -8, 0)
    frame.who = who

    local shine = header:CreateTexture(nil, "OVERLAY")
    shine:SetSize(60, 34)
    shine:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
    pcall(shine.SetBlendMode, shine, "ADD")
    shine:SetAlpha(0)
    frame.shine = shine

    -- The hero: the total, big, counting up.
    local hero = CreateFrame("Frame", nil, frame)
    hero:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    hero:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
    hero:SetHeight(66)
    frame.hero = hero
    frame.heroWash = Wash(hero)

    local amount = Theme.CreateLabel(hero, 26, "accent", "CENTER")
    pcall(amount.SetFont, amount, Theme.FONT, 26, "OUTLINE")
    Bright(amount)
    amount:SetPoint("TOP", 0, -8)
    frame.amount = amount

    local sources = Theme.CreateLabel(hero, "small", "muted", "CENTER")
    sources:SetPoint("TOP", amount, "BOTTOM", 0, -8)
    frame.sources = sources

    frame.sparks = {}
    for index = 1, #SPARKS do
        local spark = hero:CreateTexture(nil, "OVERLAY")
        spark:SetSize(3, 3)
        spark:SetColorTexture(BRIGHT_GOLD[1], BRIGHT_GOLD[2], BRIGHT_GOLD[3], 1)
        pcall(spark.SetBlendMode, spark, "ADD")
        spark:SetAlpha(0)
        frame.sparks[index] = spark
    end

    -- The record ribbon, shown when the visit beat something.
    local ribbon = CreateFrame("Frame", nil, frame)
    ribbon:SetHeight(24)
    Theme.Fill(ribbon, "rowActive")
    Theme.Border(ribbon, "accent", 0.8)
    ribbon.wash = Wash(ribbon, "BORDER")
    ribbon.text = Theme.CreateLabel(ribbon, "normal", "accent", "CENTER")
    pcall(ribbon.text.SetFont, ribbon.text, Theme.FONT, Theme.sizes.normal, "OUTLINE")
    Bright(ribbon.text)
    ribbon.text:SetPoint("CENTER")
    ribbon:Hide()
    frame.ribbon = ribbon

    frame.rows = {}

    -- Footer: the day, the week and the best haul, then the buttons.
    local stats = Theme.CreateLabel(frame, "tiny", "muted", "CENTER")
    stats:SetPoint("BOTTOMLEFT", PAD, 44)
    stats:SetPoint("BOTTOMRIGHT", -PAD, 44)
    frame.stats = stats

    local done = Widgets.CreateButton(frame, "Close", function() frame:Hide() end,
        { width = 110, height = 24, primary = true })
    done:SetPoint("BOTTOMRIGHT", -PAD, 14)

    local visits = Widgets.CreateButton(frame, "See all visits", function()
        frame:Hide()
        MailReport:OpenVisits()
    end, { width = 130, height = 24, tooltip = "Every mailbox visit, on the Sales tab" })
    visits:SetPoint("BOTTOMLEFT", PAD, 14)

    self.frame = frame
    return frame
end

--- A pooled row of the report.
local function Row(frame, index)
    local row = frame.rows[index]
    if row then return row end

    row = CreateFrame("Frame", nil, frame)
    row:SetHeight(ROW)

    row.glow = Wash(row)

    row.icon = Theme.CreateItemIcon(row, 16)
    row.icon:SetPoint("LEFT", 0, 0)

    row.label = Theme.CreateLabel(row, "small", "text")
    row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
    row.value:SetPoint("RIGHT", 0, 0)

    row.tag = Theme.CreateLabel(row, "tiny", "accent", "RIGHT")
    Bright(row.tag)

    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetColorTexture(Theme.Unpack("border"))
    row.rule:SetHeight(1)

    row.bar = Theme.CreateBar(row, 90, 3)

    frame.rows[index] = row
    return row
end

local function ResetRow(row)
    row.icon:Hide()
    row.rule:Hide()
    row.tag:Hide()
    row.bar:Set(nil)
    row.glow:SetAlpha(0)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.label:SetFont(Theme.FONT, Theme.sizes.small, "")
    row.label:SetTextColor(Theme.Unpack("text"))
    row.value:SetWidth(0)
    row.value:SetText("")
    row.value:SetTextColor(Theme.Unpack("text"))
    row:SetAlpha(1)
end

--- Fill one row from a line of MailReport.Lines.
local function DrawLine(row, line)
    ResetRow(row)

    if line.type == "heading" then
        row.label:SetFont(Theme.FONT, Theme.sizes.tiny, "")
        row.label:SetTextColor(Theme.Unpack("accent"))
        row.label:ClearAllPoints()
        row.label:SetPoint("BOTTOMLEFT", 0, 3)
        row.label:SetText(line.text)
        row.rule:ClearAllPoints()
        row.rule:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.rule:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.rule:Show()

    elseif line.type == "money" then
        row.label:SetText(line.label)
        row.value:SetText(Util.FormatMoney(line.amount))
        row.value:SetTextColor(Theme.Unpack(line.color or "text"))
        row.value:SetWidth(120)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 0, 0)
        row.bar.track:ClearAllPoints()
        row.bar.track:SetPoint("RIGHT", row.value, "LEFT", -10, 0)
        row.bar:Set(0.001, line.color == "text" and "accent" or line.color)

    elseif line.type == "sale" then
        Theme.SetItemIcon(row.icon, line.itemID)
        if not line.itemID then row.icon:Hide() end
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", line.itemID and 22 or 0, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
        row.label:SetText(ItemText(line.itemID, line.name))
        local r, g, b = Util.GetItemQualityColor(line.itemID)
        if r then row.label:SetTextColor(r, g, b) end
        row.value:SetText(Util.FormatMoney(line.amount))
        row.value:SetTextColor(Theme.Unpack("profit"))
        row.value:SetWidth(110)

        if line.best then
            row.label:SetFont(Theme.FONT, Theme.sizes.normal, "")
            if line.record then
                row.tag:ClearAllPoints()
                row.tag:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
                row.tag:SetText("BEST EVER")
                row.tag:Show()
                row.label:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
            end
        end

    else
        row.label:SetText(line.label)
        row.label:SetTextColor(Theme.Unpack(line.color or "text"))
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 0, 0)
        row.value:SetText(line.text or "")
        row.value:SetTextColor(Theme.Unpack("muted"))
        row.value:SetWidth(WIDTH - 2 * PAD - 150)
    end
end

--- The character's name for a haul's key. Keys are now the character's GUID
--- ("Player-..."), where the text before the first dash is just "Player", so
--- the name comes from the character's record; old "Name-Realm" keys still
--- work. Empty when the character is unknown.
function MailReport.WhoName(key)
    return Util.CharacterName(key)
end

--- "Blackthornes, just now" or "Blackthornes, 2h ago"
local function WhoWhen(haul)
    local name = MailReport.WhoName(haul.who)
    local age = haul.t and (time() - haul.t) or 0
    local when = age < 60 and "just now" or Util.FormatAgeAgo(age)
    if name == "" then return when end
    return ("%s, %s"):format(name, when)
end

--- Show the report for a haul. `opts.replay` when reopening an old one.
function MailReport:Show(haul, opts)
    opts = opts or {}
    local frame = self:Build()

    StopAll("report")

    frame.who:SetText(haul.sample and "sample" or WhoWhen(haul))
    frame.sources:SetText(MailReport.Sources(haul))
    frame.amount:SetText(Util.FormatMoney(0))

    -- The record ribbon.
    local ribbonText
    -- Reopened from the Sales tab, a record is told as one it was then,
    -- not as news.
    if haul.recordHaul then
        ribbonText = (opts.replay and "BEST HAUL AT THE TIME!  Old best %s" or "NEW BEST HAUL!  Old best %s"):format(
            Util.FormatMoney(haul.previousBest or 0, { short = true }))
    elseif haul.recordSale then
        ribbonText = opts.replay and "BEST SALE AT THE TIME!" or "YOUR BEST SALE EVER!"
    elseif haul.first then
        ribbonText = "YOUR FIRST HAUL ON RECORD"
    end

    local y = -(6 + 34 + 4 + 66)

    if ribbonText then
        frame.ribbon:ClearAllPoints()
        frame.ribbon:SetPoint("TOPLEFT", PAD, y - 2)
        frame.ribbon:SetPoint("TOPRIGHT", -PAD, y - 2)
        frame.ribbon.text:SetText(ribbonText)
        frame.ribbon:SetAlpha(0)
        frame.ribbon:Show()
        y = y - 32
    else
        frame.ribbon:Hide()
    end

    -- The rows.
    local lines = MailReport.Lines(haul)
    for index, line in ipairs(lines) do
        local row = Row(frame, index)
        local gap = (line.type == "heading" and index > 1) and 8 or 0
        y = y - gap

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, y)
        row:SetPoint("TOPRIGHT", -PAD, y)
        row:SetHeight(line.best and 24 or ROW)
        DrawLine(row, line)
        row:Show()

        -- Each row fades in after the one above, and a share bar slides out.
        row:SetAlpha(0)
        local delay = 0.25 + index * 0.06
        MailReport.Start({ slot = "report:row" .. index, duration = 0.3, delay = delay,
            apply = function(p) row:SetAlpha(EaseOut(p)) end,
            stop = function() row:SetAlpha(1) end })

        if line.type == "money" then
            MailReport.Start({ slot = "report:bar" .. index, duration = 0.8, delay = delay + 0.1,
                apply = function(p) row.bar:Set(math.max(0.001, line.share * EaseOut(p)),
                    line.color == "text" and "accent" or line.color) end,
                stop = function() row.bar:Set(line.share, line.color == "text" and "accent" or line.color) end })
        end

        if line.best then
            -- The best sale beats gold for a while.
            MailReport.Start({ slot = "report:best", duration = 2.4, delay = delay + 0.2,
                apply = function(p) row.glow:SetAlpha(0.16 * math.sin(p * 3 * math.pi) ^ 2) end,
                stop = function() row.glow:SetAlpha(0) end })
        end

        y = y - (line.best and 24 or ROW)
    end

    for index = #lines + 1, #frame.rows do frame.rows[index]:Hide() end

    -- The footer.
    local stats = {}
    if (haul.today or 0) > 0 then
        stats[#stats + 1] = ("Today %s"):format(Util.FormatMoney(haul.today, { short = true }))
    end
    if (haul.week or 0) > 0 then
        stats[#stats + 1] = ("Last 7 days %s"):format(Util.FormatMoney(haul.week, { short = true }))
    end
    local bestHaul = ns.MailHaul and ns.MailHaul:Records() or 0
    if bestHaul > 0 then
        stats[#stats + 1] = ("Best haul %s"):format(Util.FormatMoney(bestHaul, { short = true }))
    end
    frame.stats:SetText(table.concat(stats, "   ·   "))

    frame:SetHeight(-y + 16 + 62)
    frame:SetAlpha(0)
    frame:Show()
    if frame.Raise then frame:Raise() end

    self:Animate(haul, ribbonText ~= nil, opts)
end

--- The opening: fade in, the shine, the count-up, the pop, the ribbon.
function MailReport:Animate(haul, hasRibbon, opts)
    local frame = self.frame
    local record = haul.recordHaul or haul.recordSale

    MailReport.Start({ slot = "report:open", duration = 0.25,
        apply = function(p)
            frame:SetAlpha(EaseOut(p))
        end,
        stop = function() frame:SetAlpha(1) end })

    local okWidth, width = pcall(frame.header.GetWidth, frame.header)
    width = okWidth and tonumber(width) or WIDTH

    MailReport.Start({ slot = "report:shine", duration = 0.9, delay = 0.15,
        apply = function(p)
            frame.shine:ClearAllPoints()
            frame.shine:SetPoint("LEFT", frame.header, "LEFT", (width - 60) * p, 0)
            frame.shine:SetAlpha(0.3 * math.sin(p * math.pi))
        end,
        stop = function() frame.shine:SetAlpha(0) end })

    local countTime = math.min(2.2, 1.0 + 0.1 * math.log10(math.max(10, haul.total or 0)))

    MailReport.Play("haul")

    CountUp("report:count", frame.amount, 0, haul.total or 0, countTime, 0.2, function()
        Pop("report:pop", frame.amount, 26, 0)

        MailReport.Start({ slot = "report:wash", duration = 0.9,
            apply = function(p) frame.heroWash:SetAlpha(0.14 * (1 - p)) end,
            stop = function() frame.heroWash:SetAlpha(0) end })

        if record then MailReport.Play("record") end
    end)

    if hasRibbon then
        local ribbon = frame.ribbon
        local ribbonDelay = 0.2 + countTime

        MailReport.Start({ slot = "report:ribbon", duration = 3.0, delay = ribbonDelay,
            apply = function(p)
                ribbon:SetAlpha(math.min(1, p * 8))
                ribbon.wash:SetAlpha(0.1 + 0.1 * math.sin(p * 8 * math.pi))
                if p >= 1 then ribbon.wash:SetAlpha(0.06) end
            end,
            stop = function() ribbon:SetAlpha(1); ribbon.wash:SetAlpha(0.06) end })

        if record then
            local heroWidth = width
            for index, spark in ipairs(frame.sparks) do
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", frame.hero, "TOPLEFT",
                    SPARKS[index][1] * heroWidth, -SPARKS[index][2] * 66)
            end

            MailReport.Start({ slot = "report:sparks", duration = 3.0, delay = ribbonDelay,
                apply = function(p)
                    local fade = p > 0.7 and (1 - p) / 0.3 or 1
                    for index, spark in ipairs(frame.sparks) do
                        spark:SetAlpha(fade * (0.5 + 0.5 * math.sin(p * 14 * math.pi + index * 1.7)))
                    end
                end,
                stop = function()
                    for _, spark in ipairs(frame.sparks) do spark:SetAlpha(0) end
                end })
        end
    end
end

function MailReport:Hide()
    if self.frame then self.frame:Hide() end
end

--- Open the main window on the Sales tab's list of visits.
function MailReport:OpenVisits()
    if not ns.UI then return end
    ns.UI:Show()
    if ns.SalesTab and ns.SalesTab.ShowVisits then ns.SalesTab.ShowVisits() end
    ns.UI:SelectTab("sales")
end

--------------------------------------------------------------------------------
-- The tally over the mailbox
--------------------------------------------------------------------------------

function MailReport:BuildTally()
    if self.tally then return self.tally end

    local tally = CreateFrame("Frame", nil, UIParent)
    tally:SetSize(250, 44)
    tally:SetFrameStrata("HIGH")
    Theme.Fill(tally, "window", 0.92)
    Theme.Border(tally, "accent", 0.6)
    Theme.AccentStripe(tally, 3)
    Theme.TopSheen(tally, 0.08)
    tally.wash = Wash(tally, "BORDER")
    tally:Hide()

    local heading = Theme.CreateLabel(tally, "tiny", "accent")
    heading:SetPoint("TOPLEFT", 12, -6)
    heading:SetText("COLLECTED THIS VISIT")

    -- Trent, 2026-09-28: "i see no way to get rid of the message". A close
    -- button, and the tally also goes by itself once the mailbox is gone.
    local close = Widgets.CreateButton(tally, "X", function() MailReport:HideTally() end,
        { width = 18, height = 16, fontSize = "tiny", tooltip = "Hide this until the next mailbox visit" })
    close:SetPoint("TOPRIGHT", -4, -4)
    tally.close = close

    local count = Theme.CreateLabel(tally, "tiny", "muted", "RIGHT")
    count:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, -2)
    tally.count = count

    -- A check once a second that the mailbox is still there, whatever the
    -- game did or did not say when it closed.
    local since = 0
    tally:SetScript("OnUpdate", function(_, elapsed)
        since = since + (tonumber(elapsed) or 0)
        if since < 1 then return end
        since = 0
        if not MailReport.MailboxOpen() then MailReport:FadeTally() end
    end)

    local amount = Theme.CreateLabel(tally, 16, "accent")
    pcall(amount.SetFont, amount, Theme.FONT, 16, "OUTLINE")
    Bright(amount)
    amount:SetPoint("BOTTOMLEFT", 12, 6)
    tally.amount = amount

    tally.floats = {}
    for index = 1, 4 do
        local float = Theme.CreateLabel(tally, 14, "profit")
        pcall(float.SetFont, float, Theme.FONT, 14, "OUTLINE")
        float:Hide()
        tally.floats[index] = float
    end
    tally.nextFloat = 1

    self.tally = tally
    return tally
end

--- Put the tally just above the mailbox window, or near the top of the
--- screen if the mailbox is not the game's own.
local function PlaceTally(tally)
    tally:ClearAllPoints()
    local mailFrame = _G.MailFrame
    if mailFrame and mailFrame.IsShown and mailFrame:IsShown() then
        tally:SetPoint("BOTTOMLEFT", mailFrame, "TOPLEFT", 0, 6)
    else
        tally:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

--- "+3g 20s" rising off the right of the tally.
local function Float(tally, text)
    local float = tally.floats[tally.nextFloat]
    tally.nextFloat = tally.nextFloat % #tally.floats + 1

    float:SetText(text)
    float:Show()

    MailReport.Start({ slot = "tally:float" .. tostring(float), duration = 1.4,
        apply = function(p)
            float:ClearAllPoints()
            float:SetPoint("LEFT", tally, "RIGHT", 8, -4 + 30 * EaseOut(p))
            float:SetAlpha(p < 0.15 and p / 0.15 or 1 - (p - 0.15) / 0.85)
            if p >= 1 then float:Hide() end
        end,
        stop = function() float:Hide() end })
end

--- Is a mailbox open right now? The game's own window is the first word.
function MailReport.MailboxOpen()
    local mailFrame = _G.MailFrame
    if mailFrame and mailFrame.IsShown then
        local ok, shown = pcall(mailFrame.IsShown, mailFrame)
        if ok then return shown and true or false end
    end
    return ns.Mail and ns.Mail.isOpen == true
end

function MailReport:HideTally()
    StopAll("tally")
    self.tallyFading = false
    if self.tally then
        self.tally:Hide()
        self.tally:SetAlpha(1)
    end
    self.tallyDismissed = true
end

-- Trent, 2026-09-28: "it should fade on it's own 30sec after leaving mailbox".
local TALLY_LINGER = 30
local TALLY_FADE = 1.5

--- Leave the tally up for a while after the mailbox closes, then fade it.
function MailReport:FadeTally()
    local tally = self.tally
    if not (tally and tally:IsShown()) or self.tallyFading then return end

    self.tallyFading = true
    MailReport.Start({ slot = "tally:fade", duration = TALLY_FADE, delay = TALLY_LINGER,
        apply = function(p)
            tally:SetAlpha(1 - p)
            if p >= 1 then
                tally:Hide()
                tally:SetAlpha(1)
                MailReport.tallyFading = false
            end
        end,
        stop = function()
            tally:SetAlpha(1)
            MailReport.tallyFading = false
        end })
end

function MailReport:OnMailboxOpened()
    StopAll("tally")
    if self.tally then self.tally:Hide() end
    self.tallyShown = 0
    self.tallyDismissed = false
end

function MailReport:OnMailboxClosed()
    self:FadeTally()
end

--- Something was just collected. Logic/MailHaul.lua calls this.
function MailReport:OnCollected(visit, gained)
    if ns.Config:Get("mailReport") == false then return end
    if (visit.total or 0) <= 0 then return end
    if self.tallyDismissed then return end

    local tally = self:BuildTally()
    if not tally:IsShown() then
        PlaceTally(tally)
        tally:Show()
    end

    local sales = #(visit.sales or {})
    tally.count:SetText(sales > 0 and Plural(sales, "sale") or "")

    local from = self.tallyShown or 0
    self.tallyShown = visit.total
    CountUp("tally:count", tally.amount, from, visit.total, 0.6, 0)

    if gained > 0 then
        Float(tally, "+" .. Util.FormatMoney(gained, { short = true }))

        MailReport.Start({ slot = "tally:wash", duration = 0.6,
            apply = function(p) tally.wash:SetAlpha(0.18 * (1 - p)) end,
            stop = function() tally.wash:SetAlpha(0) end })
    end
end
