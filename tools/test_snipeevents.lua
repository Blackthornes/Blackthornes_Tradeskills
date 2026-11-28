-- Snipe and Disenchant Quick Buy hear the auction house in the game.
--
-- Both set up their events in Init, but the addon only ever runs
-- OnInitialize and OnEnable (Core/Init.lua, RunLifecycle). Nothing called
-- Init, so in the game Snipe never heard COMMODITY_SEARCH_RESULTS_UPDATED,
-- sat on "Checking..." and gave up with "the auction house is busy". The
-- other tests call Init by hand, which hid it.
--
-- What must hold:
--   1. Running the addon's own steps (OnInitialize, then OnEnable) signs
--      each module up for the events it buys with.
--   2. A second OnEnable signs nothing up twice.

local function Load(file, moduleName)
    local ns = {}
    ns.NewModule = function(name) local m = { moduleName = name }; ns[name] = m; return m end
    ns.Util = { HasFunction = function() return true end, FormatMoney = tostring }
    ns.Print = function() end
    ns.Notice = { Show = function() end }
    ns.Config = { Get = function() return nil end }
    local signed = {}
    ns.RegisterEvent = function(_, event)
        signed[event] = (signed[event] or 0) + 1
        return true
    end
    assert(loadfile(lfs_cwd .. "/" .. file))("Blackthornes_TS", ns)
    local module = ns[moduleName]
    assert(module, file .. " made no module " .. moduleName)
    -- The same two steps, in the same order, as RunLifecycle in Core/Init.lua.
    for _, step in ipairs({ "OnInitialize", "OnEnable" }) do
        if type(module[step]) == "function" then module[step](module) end
    end
    return module, signed
end

local function Check(file, moduleName, events)
    local module, signed = Load(file, moduleName)
    for _, event in ipairs(events) do
        assert(signed[event] == 1, moduleName .. " never hears " .. event .. " in the game")
    end
    print("ok 1 " .. moduleName .. " signs up for its events at login")

    module:OnEnable()
    for event, count in pairs(signed) do
        assert(count == 1, moduleName .. " signed up for " .. event .. " " .. count .. " times")
    end
    print("ok 2 " .. moduleName .. " signs up only once")
end

Check("Logic/Snipe.lua", "Snipe", {
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED",
    "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_CLOSED",
})
Check("Logic/DisenchantQuickBuy.lua", "DisenchantQuickBuy", {
    "ITEM_SEARCH_RESULTS_UPDATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_CLOSED",
})
