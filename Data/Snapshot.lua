-- Blackthornes Tradeskills -- Data/Snapshot.lua
--
-- An optional persistence fallback, and deliberately empty as shipped.
--
-- The WoW: Forever beta writes SavedVariables correctly but does not always
-- read them back, so a session can start with no saved data. The addon does
-- not depend on this file to cope with that: recipes are re-read when a
-- profession window opens, inventory and auctions are read live, and the
-- auction scan re-runs by itself. Everything rebuilds without intervention.
--
-- A developer can regenerate this from their own saved data with
-- tools/restore.ps1 to carry a database between sessions while the bug lasts.
-- It must never be distributed with data in it: that would seed another
-- player's database with someone else's characters and prices.

BlackthornesTSSnapshot = nil
