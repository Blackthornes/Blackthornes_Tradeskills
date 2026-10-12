-- Blackthornes Tradeskills -- Locale/deDE.lua
-- Deutsch (German): the words players see, on a German client.
--
-- Each line is the English key (exactly as the code writes it) and its
-- German. A key with no line here shows in English. The German speaks to
-- the player as "du", the way the game's own German does, and uses the
-- game's words (Auktionshaus, Gebot, Sofortkauf, Rezept, herstellen, Materialien,
-- entzaubern, Händler, Briefkasten, Twink, Gewinn). A line may
-- name its values by place ("%2$s ... %1$s") where
-- German word order needs it; L.Format puts them in order.
--
-- Item, character and skill names stay as the data or the client gives
-- them. tools/check_locale.py lists keys with no line here and lines no
-- longer used.

local _, ns = ...
local L = ns.L

local ok, locale = pcall(function() return GetLocale() end)
if not (ok and locale == "deDE") then return end
