-- Blackthornes Tradeskills -- Logic/Transfer.lua
-- Carrying the queue and settings across a session by hand.
--
-- The Forever beta does not read SavedVariables back, so everything is lost on
-- relog. Prices, recipes and professions all rebuild themselves; the craft
-- queue and your settings cannot, because they are decisions rather than
-- observations. This turns them into a short code you can paste back.
--
-- Prices are deliberately excluded: hundreds of items would make an unusable
-- string, and a single auction scan rebuilds them in about a second.
--
-- When SavedVariables start loading again this becomes redundant, and harmless.

local _, ns = ...
local L = ns.L or setmetatable({ Format = string.format }, { __index = function(_, key) return key end })

local Transfer = ns.NewModule("Transfer")

local Util = ns.Util

-- Bump when the format changes so an old code is rejected rather than
-- misinterpreted into nonsense.
local FORMAT = "BTS1"

-- Pipe is WoW's colour escape, so it is avoided entirely in the code.
local SECTION_SEP = "~"
local RECORD_SEP = ";"
local FIELD_SEP = ":"

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

local function EncodeSettings()
    local parts = { "S" }

    for key, default in pairs(ns.Config.DEFAULTS.settings) do
        local value = ns.Config:Get(key)

        -- Only what has been changed: a code full of defaults is noise, and
        -- makes it harder to see what was actually customised.
        if value ~= nil and value ~= default then
            if type(value) == "boolean" then
                parts[#parts + 1] = key .. "=" .. (value and "1" or "0")
            elseif type(value) == "number" then
                parts[#parts + 1] = key .. "=" .. tostring(value)
            end
        end
    end

    return table.concat(parts, RECORD_SEP)
end

local function EncodeQueue()
    local parts = { "Q" }

    for _, entry in ipairs(ns.Queue:GetAll()) do
        -- Derived sub-crafts are rebuilt from their parents, so carrying them
        -- would duplicate them on import.
        if not entry.isDependency then
            parts[#parts + 1] = entry.recipeID .. FIELD_SEP .. entry.quantity
        end
    end

    return table.concat(parts, RECORD_SEP)
end

local function EncodeLimits()
    local parts = { "L" }

    for itemID, limit in pairs(ns.db.postLimits or {}) do
        parts[#parts + 1] = itemID .. FIELD_SEP .. limit
    end

    return table.concat(parts, RECORD_SEP)
end

--- A copy-paste code carrying the queue, changed settings and posted limits.
function Transfer:Export()
    return table.concat({
        FORMAT,
        EncodeQueue(),
        EncodeSettings(),
        EncodeLimits(),
    }, SECTION_SEP)
end

--- What the export currently contains, for describing it before it is copied.
function Transfer:Describe()
    local queued, limits, settings = 0, 0, 0

    for _, entry in ipairs(ns.Queue:GetAll()) do
        if not entry.isDependency then queued = queued + 1 end
    end

    for _ in pairs(ns.db.postLimits or {}) do limits = limits + 1 end

    -- Counted the way the code writes them: only switches and numbers
    -- travel, so a changed text setting is not promised.
    for key, default in pairs(ns.Config.DEFAULTS.settings) do
        local value = ns.Config:Get(key)
        if value ~= default and (type(value) == "boolean" or type(value) == "number") then
            settings = settings + 1
        end
    end

    return queued, settings, limits
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------

--- Restore from a code.
-- @return ok, message
function Transfer:Import(code)
    code = (code or ""):gsub("%s", "")

    if code == "" then
        return false, L["nothing to import"]
    end

    local sections = {}
    for section in code:gmatch("[^" .. SECTION_SEP .. "]+") do
        sections[#sections + 1] = section
    end

    if sections[1] ~= FORMAT then
        return false, L["that does not look like a Blackthornes Tradeskills code"]
    end

    local queued, settingsApplied, limitsApplied = 0, 0, 0
    local skipped = 0
    local resized = false

    for index = 2, #sections do
        local section = sections[index]
        local kind = section:sub(1, 1)

        for record in section:sub(2):gmatch("[^" .. RECORD_SEP .. "]+") do
            if kind == "Q" then
                local recipeID, quantity = record:match("^(%d+)" .. FIELD_SEP .. "(%d+)$")

                if recipeID then
                    -- Only recipes this character actually knows. A code from
                    -- another character would otherwise queue crafts that can
                    -- never be made.
                    if ns.Recipes:GetAny(tonumber(recipeID)) then
                        -- A craft already queued is set to the code's
                        -- amount, not added to. Adding meant importing the
                        -- same code twice doubled the queue.
                        local _, existing = ns.Queue:Find(tonumber(recipeID), true)
                        if existing then
                            existing.quantity = math.max(1, math.floor(tonumber(quantity) or 1))
                            resized = true
                        else
                            ns.Queue:Add(tonumber(recipeID), tonumber(quantity))
                        end
                        queued = queued + 1
                    else
                        skipped = skipped + 1
                    end
                end

            elseif kind == "S" then
                local key, value = record:match("^(%w+)=(.+)$")
                local default = key and ns.Config.DEFAULTS.settings[key]

                -- Unknown keys are ignored rather than written blindly, and the
                -- default's type decides how the value is read.
                if default ~= nil then
                    if type(default) == "boolean" then
                        ns.Config:Set(key, value == "1")
                        settingsApplied = settingsApplied + 1
                    elseif type(default) == "number" and tonumber(value) then
                        ns.Config:Set(key, tonumber(value))
                        settingsApplied = settingsApplied + 1
                    end
                end

            elseif kind == "L" then
                local itemID, limit = record:match("^(%d+)" .. FIELD_SEP .. "(%d+)$")

                if itemID then
                    ns.Auctions:SetLimit(tonumber(itemID), tonumber(limit))
                    limitsApplied = limitsApplied + 1
                end
            end
        end
    end

    if resized then
        ns.Queue:RebuildDependencies()
        ns.Queue:Notify()
    end

    local summary
    if skipped > 0 then
        -- Said plainly: silently dropping crafts would look like data loss.
        summary = L.Format("restored %d craft(s), %d setting(s), %d limit(s); skipped %d recipe(s) none of your characters know",
            queued, settingsApplied, limitsApplied, skipped)
    else
        summary = L.Format("restored %d craft(s), %d setting(s), %d limit(s)",
            queued, settingsApplied, limitsApplied)
    end

    if ns.UI then
        -- A code can carry the window's size: drawn at it now, not next time.
        if ns.UI.ApplyScale then ns.UI:ApplyScale() end
        ns.UI:RefreshActiveTab()
        ns.UI:UpdateHeader()
    end

    return true, summary
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

ns.RegisterCommand("export", L["copy your queue and settings to a code"], function()
    if ns.UI then ns.UI:ShowTransferDialog("export") end
end)

-- The chat box holds 255 letters, the command included, and quietly drops
-- whatever is pasted past that. A cut code still reads as a code: its last
-- number comes in short, and any section after the cut is missing. So a code
-- long enough to have been cut is never imported from chat. The room is
-- reckoned from the longer command, with a few letters spare for spaces.
local CHAT_ROOM = 255 - #"/blackthorne import " - 5

ns.RegisterCommand("import", L["restore your queue and settings from a code"], function(args)
    -- Pasting into the box is easier than typing after the command, but accept
    -- both rather than insisting.
    if args and args:gsub("%s", "") ~= "" then
        if #args < CHAT_ROOM then
            local ok, message = ns.Transfer:Import(args)
            ns.Print(message)
            return ok
        end

        ns.Print(L["that code is too long for the chat box, which cuts it short. Paste it into this window instead."])
    end

    if ns.UI then ns.UI:ShowTransferDialog("import") end
end)
