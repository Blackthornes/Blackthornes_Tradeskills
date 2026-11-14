-- TEMPORARY DEBUG: REMOVE BEFORE RELEASE.
--
-- Traces "wheel up to list" on the auction house Sell tab, to find why it
-- works for a while and then stops. Developer only, English only, no locale
-- strings, nothing saved. Off until the player types /bts debug scroll
-- (again turns it off; a /reload turns it off too).
--
-- Everything lives in this one file. It wraps existing methods from the
-- outside and changes nothing they do. To take it out: delete this file and
-- the marked line at the end of Blackthornes_TS.toc. tools/check_package.py
-- refuses a release zip that still holds a Debug folder.

local _, ns = ...

local Trace = { on = false, turn = 0, parts = nil, lastBind = nil }

local PREFIX = "|cffff8800[scroll]|r "

local function Say(text)
    if ns.PrintRaw then ns.PrintRaw(PREFIX .. text) else print(PREFIX .. text) end
end

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function YN(v)
    if v == nil then return "nil" end
    return v and "y" or "n"
end

local function Safe(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return "ERR:" .. tostring(a)
end

local function ItemName(itemID)
    if not itemID then return "?" end
    local name
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, itemID)
        if ok then name = n end
    end
    if not name and type(GetItemInfo) == "function" then
        local ok, n = pcall(GetItemInfo, itemID)
        if ok then name = n end
    end
    return (name or "item") .. "#" .. tostring(itemID)
end

-- Adds one step to the line the current turn prints, or prints it alone
-- when it happens outside a turn (a click on List Next, a late answer).
local function Step(text)
    if not Trace.on then return end
    if Trace.parts then
        Trace.parts[#Trace.parts + 1] = text
    else
        Say(text)
    end
end

local function QueueState()
    local Q = ns.AHQueue
    if not Q then return "q=?" end
    local urgent = Q.PRIORITY and Q.PRIORITY.urgent
    local why = Safe(Q.WhyNotReady, Q, urgent)
    local wait = Safe(Q.SecondsUntilReady, Q, urgent)
    local sent = Safe(Q.RecentSendCount, Q)
    local queued = Safe(Q.GetPendingCount, Q)
    return ("q[sent15s=%s queued=%s wait=%s why=%s]"):format(
        tostring(sent), tostring(queued),
        type(wait) == "number" and ("%.1f"):format(wait) or tostring(wait),
        tostring(why or "-"))
end

local function PostingState(itemID)
    local P = ns.Posting
    if not P then return "posting=?" end
    local pending = Safe(P.AllPending, P)
    local count = type(pending) == "table" and #pending or tostring(pending)
    local scanner = ns.Scanner
    return ("post[ah=%s blocked=%s scanBlocks=%s throttled=%s confirming=%s full=%s]"):format(
        YN(scanner and scanner.isAuctionHouseOpen),
        YN(Safe(P.IsBlocked, P)), YN(Safe(P.ScanBlocks, P)), YN(Safe(P.IsThrottled, P)),
        tostring(count), YN(Safe(P.ConfirmingFull, P, itemID)))
end

local function Wrap(module, method, wrapper)
    if type(module) ~= "table" or type(module[method]) ~= "function" then
        Say(("could not wrap %s"):format(method))
        return
    end
    local original = module[method]
    module[method] = function(self, ...)
        if not Trace.on then return original(self, ...) end
        return wrapper(original, self, ...)
    end
end

local function Install()
    if Trace.installed then return end
    Trace.installed = true

    local Wheel, Panel, Posting = ns.AuctionWheel, ns.PostPanel, ns.Posting

    -- One turn of the wheel: what the wheel saw before it acted.
    Wrap(Wheel, "Turn", function(original, self, up)
        Trace.turn = Trace.turn + 1
        local now = Now()
        local gap = self.lastAt and ("%.2f"):format(now - self.lastAt) or "first"
        local panel = ns.PostPanel
        Trace.parts = {
            ("#%d t=%.1f %s view=%s wanted=%s job=%s gap=%s bound=%s holds=%s"):format(
                Trace.turn, now % 1000, up and "UP" or "DOWN",
                tostring(panel and panel.view), YN(Safe(self.Wanted, self)),
                tostring(Safe(self.Job, self)), gap, YN(self.bound),
                YN(Safe(self.Holds, self))),
        }
        local results = { pcall(original, self, up) }
        local parts = Trace.parts
        Trace.parts = nil
        if not results[1] then
            parts[#parts + 1] = "ERROR " .. tostring(results[2])
        else
            parts[#parts + 1] = "turn->" .. tostring(results[2])
            if results[2] == false then
                parts[#parts + 1] = "(bailed in Turn: not wanted, no job or too soon)"
            end
        end
        Say(table.concat(parts, " | "))
        if not results[1] then error(results[2], 0) end
        return results[2]
    end)

    -- The Sell tab's choice: which stack, and which path it will take.
    Wrap(Panel, "ListNext", function(original, self)
        local P = ns.Posting
        local lines = self.shownLines or Safe(self.ShownLines, self)
        local count = type(lines) == "table" and #lines or tostring(lines)
        local fast = P.FastListing ~= nil and Safe(P.FastListing, P)
        local line, settling = Safe(P.GetNextPostable, P,
            fast == true and { skipSettling = true } or nil, type(lines) == "table" and lines or nil)
        if type(line) ~= "table" then
            Step(("lines=%d fast=%s next=none settling=%s -> stop"):format(
                tonumber(count) or 0, YN(fast), YN(settling)))
            return original(self)
        end
        local id = line.itemID
        local fresh = Safe(P.IsFresh, P, id)
        local bulk = Safe(P.BulkTried, P, id)
        local checking = Safe(P.CheckPending, P, id)
        local verify = ns.Config and ns.Config:Get("verifyPriceBeforePosting") ~= false
        local path
        if fast == true and fresh ~= true and bulk ~= true and verify then
            path = "checkall?"
        else
            local ok, why = Safe(P.CanPost, P, id)
            path = ok == true and "request" or ("refused:" .. tostring(why))
        end
        Step(("lines=%s fast=%s next=%s x%s @%s settling=%s fresh=%s bulkTried=%s checkPending=%s verify=%s path=%s"):format(
            tostring(count), YN(fast), ItemName(id), tostring(line.postQuantity),
            tostring(line.unitPrice), YN(settling), YN(fresh), YN(bulk), YN(checking),
            YN(verify), path))
        Step(PostingState(id))
        Step(QueueState())
        return original(self)
    end)

    Wrap(Posting, "CheckAll", function(original, self, lines)
        local started, count = original(self, lines)
        Step(("checkAll started=%s count=%s"):format(YN(started), tostring(count)))
        return started, count
    end)

    Wrap(Posting, "Request", function(original, self, itemID, quantity, unitPrice)
        local onClick = Safe(self.CanListOnClick, self, itemID, unitPrice)
        Step(("request %s listOnClick=%s asksFirst=%s"):format(
            ItemName(itemID), YN(onClick), YN(Safe(self.AsksFirst, self))))
        local result = original(self, itemID, quantity, unitPrice)
        Step("request->" .. tostring(result))
        return result
    end)

    Wrap(Posting, "Post", function(original, self, itemID, quantity, unitPrice, byHand)
        local a, b = original(self, itemID, quantity, unitPrice, byHand)
        Step(("post %s x%s @%s -> %s %s"):format(ItemName(itemID), tostring(quantity),
            tostring(unitPrice), tostring(a), b ~= nil and tostring(b) or ""))
        return a, b
    end)

    Wrap(Posting, "RefusesEarly", function(original, self, itemID, price, byHand)
        local refused = original(self, itemID, price, byHand)
        if refused then Step("refusedEarly " .. ItemName(itemID)) end
        return refused
    end)

    Wrap(Posting, "AskFarUnder", function(original, self, ...)
        Step("askFarUnder (box shown)")
        return original(self, ...)
    end)

    Wrap(Posting, "Confirm", function(original, self, itemID, ...)
        Step("confirm box " .. ItemName(itemID))
        return original(self, itemID, ...)
    end)

    -- The binding: printed only when it changes, to catch the wheel being
    -- taken away from us.
    Wrap(Wheel, "Update", function(original, self, ...)
        local result = original(self, ...)
        local state = ("want=%s bound=%s holds=%s waiting=%s"):format(
            YN(Safe(self.Wanted, self)), YN(self.bound), YN(Safe(self.Holds, self)), YN(self.waiting))
        if state ~= Trace.lastBind then
            Trace.lastBind = state
            Say("bind " .. state)
        end
        return result
    end)
end

local function Toggle()
    Install()
    Trace.on = not Trace.on
    Trace.lastBind = nil
    if Trace.on then
        Trace.turn = 0
        Say("trace ON. Turn the wheel on the Sell tab. No line on a turn means the turn never reached Tradeskills.")
        if ns.AuctionWheel and ns.AuctionWheel.Update then pcall(ns.AuctionWheel.Update, ns.AuctionWheel) end
    else
        Say("trace OFF.")
    end
end

-- The one hook: /bts debug scroll. Plain /bts debug works as before.
local command = ns.commands and ns.commands.debug
if command and type(command.fn) == "function" then
    local original = command.fn
    command.fn = function(rest, ...)
        if type(rest) == "string" and rest:lower():match("^%s*scroll") then
            Toggle()
            return
        end
        return original(rest, ...)
    end
end

ns.ScrollTrace = Trace
