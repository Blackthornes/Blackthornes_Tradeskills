-- Blackthornes Tradeskills -- UI/GoldChart.lua
-- The Sales tab's "Gold in and out": a bar chart and its legend.
--
-- Drawn from plain colour textures, like the Prices tab's history chart, so
-- it needs no art and no library. Each bar is one stretch of time: income
-- stacked up from a gold line in the middle, spending stacked down from it,
-- each source in its own colour. Hovering a bar lists what made it up.
--
-- The numbers come from Logic/GoldLog.lua; this only draws them.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Theme = ns.Theme
local Util = ns.Util

local GoldChart = {}
ns.GoldChart = GoldChart

local LEGEND_ROWS = 22
local ROW_HEIGHT = 15

--------------------------------------------------------------------------------
-- Money in words
--------------------------------------------------------------------------------

--- "+1g 20s" or "-40s", coins left plain so the green or red reads.
function GoldChart.Signed(copper)
    local sign = copper > 0 and "+" or (copper < 0 and "-" or "")
    return sign .. Util.FormatMoney(math.abs(copper), { short = true, noColor = true })
end

--------------------------------------------------------------------------------
-- The chart
--------------------------------------------------------------------------------

function GoldChart.CreateChart(parent)
    local chart = CreateFrame("Frame", nil, parent)
    Theme.Recess(chart)

    -- Room inside the well for the scale on the left and the times below.
    local plot = CreateFrame("Frame", nil, chart)
    plot:SetPoint("TOPLEFT", 70, -16)
    plot:SetPoint("BOTTOMRIGHT", -14, 26)
    chart.plot = plot

    local zero = plot:CreateTexture(nil, "OVERLAY")
    zero:SetHeight(1)
    zero:SetColorTexture(Theme.Unpack("accent", 0.8))
    chart.zero = zero

    chart.top = Theme.CreateLabel(chart, "tiny", "profit", "RIGHT")
    chart.top:SetPoint("TOPRIGHT", plot, "TOPLEFT", -6, 4)
    chart.top:SetWidth(62)

    chart.bottom = Theme.CreateLabel(chart, "tiny", "loss", "RIGHT")
    chart.bottom:SetPoint("BOTTOMRIGHT", plot, "BOTTOMLEFT", -6, -4)
    chart.bottom:SetWidth(62)

    chart.zeroLabel = Theme.CreateLabel(chart, "tiny", "dim", "RIGHT")
    chart.zeroLabel:SetWidth(62)
    chart.zeroLabel:SetText("0")

    chart.empty = Theme.CreateLabel(chart, "small", "dim", "CENTER")
    chart.empty:SetPoint("CENTER", plot, "CENTER")
    chart.empty:SetWidth(360)
    chart.empty:SetWordWrap(true)

    chart.ticks = {}
    for index = 1, 3 do
        local tick = Theme.CreateLabel(chart, "tiny", "dim", "CENTER")
        tick:SetWidth(60)
        chart.ticks[index] = tick
    end

    chart.columns = {}
    return chart
end

--- One bar's frame: a hit area for the tooltip and a pool of segments.
local function Column(chart, index)
    local column = chart.columns[index]
    if column then return column end

    column = CreateFrame("Frame", nil, chart.plot)
    column:EnableMouse(true)
    column.segments = {}

    column.hover = column:CreateTexture(nil, "BACKGROUND")
    column.hover:SetAllPoints(column)
    column.hover:SetColorTexture(Theme.Unpack("rowHover", 0.5))
    column.hover:Hide()

    column:SetScript("OnEnter", function(self)
        self.hover:Show()
        GoldChart.ShowTooltip(self, self.bin)
    end)
    column:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)

    chart.columns[index] = column
    return column
end

local function Segment(column, index)
    local segment = column.segments[index]
    if not segment then
        segment = column:CreateTexture(nil, "ARTWORK")
        column.segments[index] = segment
    end
    return segment
end

--- What one bar's stretch of time took in and paid out, source by source.
function GoldChart.ShowTooltip(owner, bin)
    if not bin or not GameTooltip then return end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(bin.title or bin.label or "", 1, 1, 1)

    local income, spending = 0, 0
    for _, source in ipairs(ns.GoldLog.SOURCES) do
        local line = bin.sources[source.key]
        if line and not source.moved then
            local r, g, b = source.color[1], source.color[2], source.color[3]
            if line.i > 0 then
                GameTooltip:AddDoubleLine(source.text, GoldChart.Signed(line.i), r, g, b, Theme.Unpack("profit"))
                income = income + line.i
            end
            if line.o > 0 then
                GameTooltip:AddDoubleLine(source.text, GoldChart.Signed(-line.o), r, g, b, Theme.Unpack("loss"))
                spending = spending + line.o
            end
        end
    end

    if income == 0 and spending == 0 then
        GameTooltip:AddLine(L["No gold in or out"], Theme.Unpack("muted"))
    else
        local net = income - spending
        local r, g, b = Theme.ProfitColor(net)
        GameTooltip:AddDoubleLine(L["Net"], GoldChart.Signed(net), 1, 1, 1, r, g, b)
    end

    GameTooltip:Show()
end

--- Draw a set of bins from GoldLog:Bins.
-- @param emptyText  what to say when nothing moved
function GoldChart.SetBins(chart, bins, emptyText)
    local plot = chart.plot
    local width = plot:GetWidth()
    local height = plot:GetHeight()
    if type(width) ~= "number" or width <= 0 then width = 400 end
    if type(height) ~= "number" or height <= 0 then height = 260 end

    -- The tallest income and the deepest spending set the scale, one scale
    -- for both so a bar up and a bar down of the same size mean the same.
    local maxIn, maxOut = 0, 0
    for _, bin in ipairs(bins) do
        local income, spending = 0, 0
        for key, line in pairs(bin.sources) do
            if not ns.GoldLog:GetSource(key).moved then
                income = income + line.i
                spending = spending + line.o
            end
        end
        bin.income, bin.spending = income, spending
        if income > maxIn then maxIn = income end
        if spending > maxOut then maxOut = spending end
    end

    for _, column in ipairs(chart.columns) do column:Hide() end

    local count = #bins
    local nothing = maxIn == 0 and maxOut == 0

    chart.empty:SetShown(nothing)
    chart.empty:SetText(nothing and (emptyText or "") or "")
    chart.zero:SetShown(not nothing)
    chart.zeroLabel:SetShown(not nothing)
    chart.top:SetText(nothing and "" or GoldChart.Signed(maxIn))
    chart.bottom:SetText(nothing and "" or (maxOut > 0 and GoldChart.Signed(-maxOut) or ""))

    for _, tick in ipairs(chart.ticks) do tick:Hide() end
    if nothing or count == 0 then return end

    local scale = (height - 2) / (maxIn + maxOut)
    local zeroY = maxOut * scale

    chart.zero:ClearAllPoints()
    chart.zero:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, zeroY)
    chart.zero:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, zeroY)
    chart.zeroLabel:ClearAllPoints()
    chart.zeroLabel:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, zeroY)
    -- A zero line at the very top or bottom says nothing the scale does not.
    chart.zeroLabel:SetShown(maxIn > 0 and maxOut > 0)

    local gap = count > 40 and 1 or 2
    local slot = width / count
    local barWidth = math.max(1, slot - gap)

    for index, bin in ipairs(bins) do
        local column = Column(chart, index)
        column.bin = bin
        column:ClearAllPoints()
        column:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", (index - 1) * slot, 0)
        column:SetSize(barWidth, height)
        column:Show()

        for _, segment in ipairs(column.segments) do segment:Hide() end

        local used = 0
        local up, down = zeroY, zeroY

        for _, source in ipairs(ns.GoldLog.SOURCES) do
            local line = bin.sources[source.key]
            if line and not source.moved then
                local r, g, b = source.color[1], source.color[2], source.color[3]

                if line.i > 0 then
                    used = used + 1
                    local segment = Segment(column, used)
                    -- A sliver still shows, or a small earner vanishes
                    -- beside a big one.
                    local tall = math.max(1, line.i * scale)
                    segment:ClearAllPoints()
                    segment:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", 0, up)
                    segment:SetSize(barWidth, tall)
                    segment:SetColorTexture(r, g, b, 0.95)
                    segment:Show()
                    up = up + tall
                end

                if line.o > 0 then
                    used = used + 1
                    local segment = Segment(column, used)
                    local tall = math.max(1, line.o * scale)
                    down = down - tall
                    segment:ClearAllPoints()
                    segment:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", 0, math.max(0, down))
                    segment:SetSize(barWidth, tall)
                    segment:SetColorTexture(r, g, b, 0.75)
                    segment:Show()
                end
            end
        end
    end

    -- The first, middle and last bars' times under the chart.
    local marks = { 1 }
    if count >= 3 then marks[#marks + 1] = math.ceil(count / 2) end
    if count >= 2 then marks[#marks + 1] = count end

    for position, index in ipairs(marks) do
        local tick = chart.ticks[position]
        tick:ClearAllPoints()
        tick:SetPoint("TOP", plot, "BOTTOMLEFT", (index - 0.5) * slot, -6)
        tick:SetText(bins[index].label or "")
        tick:Show()
    end
end

--------------------------------------------------------------------------------
-- The legend
--------------------------------------------------------------------------------

function GoldChart.CreateLegend(parent, width)
    local legend = Theme.CreatePanel(parent, "window")
    Theme.AccentStripe(legend, 2, 0.6)
    legend:SetWidth(width)

    legend.title = Theme.CreateLabel(legend, "large", "accent")
    legend.title:SetPoint("TOPLEFT", 12, -12)
    legend.title:SetPoint("TOPRIGHT", -12, -12)

    legend.subtitle = Theme.CreateLabel(legend, "small", "muted")
    legend.subtitle:SetPoint("TOPLEFT", legend.title, "BOTTOMLEFT", 0, -4)
    legend.subtitle:SetPoint("TOPRIGHT", legend.title, "BOTTOMRIGHT", 0, -4)

    legend.rows = {}
    local anchor = legend.subtitle

    for index = 1, LEGEND_ROWS do
        local row = CreateFrame("Frame", nil, legend)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, index == 1 and -10 or 0)
        row:SetPoint("TOPRIGHT", legend, "TOPRIGHT", -12, 0)

        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(10, 10)
        row.swatch:SetPoint("LEFT", 2, 0)

        row.label = Theme.CreateLabel(row, "small", "text")
        row.label:SetPoint("LEFT", 18, 0)
        row.label:SetPoint("RIGHT", -100, 0)

        row.value = Theme.CreateLabel(row, "small", "text", "RIGHT")
        row.value:SetPoint("RIGHT", 0, 0)
        row.value:SetWidth(96)

        legend.rows[index] = row
        anchor = row
    end

    legend.note = Theme.CreateLabel(legend, "tiny", "dim")
    legend.note:SetPoint("BOTTOMLEFT", 12, 14)
    legend.note:SetPoint("BOTTOMRIGHT", -12, 14)
    legend.note:SetWordWrap(true)
    legend.note:SetJustifyH("LEFT")

    return legend
end

--- Fill the legend from GoldLog:Totals: income by source, spending by
--- source, the net, and gold moved between your own characters.
function GoldChart.SetTotals(legend, totals, subtitle)
    legend.title:SetText(L["Gold in and out"])
    legend.subtitle:SetText(subtitle or "")

    local lines = {}
    local function Add(text, value, valueKey, color, heading)
        lines[#lines + 1] = { text = text, value = value, valueKey = valueKey,
            color = color, heading = heading }
    end

    -- One side's sources, biggest first.
    local function Side(field, sign, valueKey)
        local found = {}
        for _, source in ipairs(ns.GoldLog.SOURCES) do
            local line = totals.sources[source.key]
            if line and line[field] > 0 and not source.moved then
                found[#found + 1] = { source = source, amount = line[field] }
            end
        end
        table.sort(found, function(a, b)
            if a.amount ~= b.amount then return a.amount > b.amount end
            return a.source.order < b.source.order
        end)
        for _, item in ipairs(found) do
            Add(item.source.text, GoldChart.Signed(sign * item.amount), valueKey, item.source.color)
        end
    end

    Add(L["Income"], GoldChart.Signed(totals.income), "profit", nil, true)
    Side("i", 1, "profit")

    Add(L["Spending"], GoldChart.Signed(-totals.spending), "loss", nil, true)
    Side("o", -1, "loss")

    Add(L["Net"], GoldChart.Signed(totals.net),
        totals.net < 0 and "loss" or (totals.net > 0 and "profit" or "muted"), nil, true)

    if totals.moved > 0 then
        local moved = totals.sources.transfer
        Add(L["Moved between alts"], Util.FormatMoney((moved and moved.i or 0) + (moved and moved.o or 0),
            { short = true, noColor = true }), "muted", nil, true)
    end

    -- More sources than rows: the smallest are the ones left off. The net
    -- and the headings are never the ones dropped.
    while #lines > LEGEND_ROWS do
        local dropAt
        for index = #lines, 1, -1 do
            if not lines[index].heading then dropAt = index break end
        end
        if not dropAt then break end
        table.remove(lines, dropAt)
    end

    for index, row in ipairs(legend.rows) do
        local line = lines[index]
        if line then
            row.label:SetText(line.text)
            row.label:SetTextColor(Theme.Unpack(line.heading and "accent" or "text"))
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", line.heading and 0 or 18, 0)
            row.label:SetPoint("RIGHT", -100, 0)
            row.value:SetText(line.value)
            row.value:SetTextColor(Theme.Unpack(line.valueKey or "text"))

            if line.color then
                row.swatch:SetColorTexture(line.color[1], line.color[2], line.color[3], 1)
                row.swatch:Show()
            else
                row.swatch:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end

    legend.note:SetText(L["Hover a bar to see what made it up. Gold mailed between your own characters is not counted as income or spending."])
end
