# Where the addon's sounds come from

Nothing here is the game's own audio: the game's sounds are played by ID,
never shipped.

- `Media/Sounds/mail-haul.ogg`, `Media/Sounds/mail-record.ogg`: made in code
  by `tools/make_sounds.py`, so they are the addon's own.
- `Media/Sounds/sale-register.ogg` (the sale alarm's "Cash register", added
  2026-10-11): one second cut from an antique cash register recording on
  Freesound, sound 452572,
  https://freesound.org/people/kyles/sounds/452572/ . License: Creative
  Commons 0 (public domain dedication), so it ships with no credit owed.
  Cut from 62.68 s for 1.1 s, high-passed at 120 Hz, faded in over 8 ms and
  out over the last 0.3 s, levelled to about -3 dB peak, mono 44.1 kHz Ogg
  Vorbis.

The sale alarm's "Coins" is the game's own loot coin sound, played by file ID
567413; "Raid warning" is the game's SOUNDKIT.RAID_WARNING (8959).
