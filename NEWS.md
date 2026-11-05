# News

What each release says in the Discord server's #general channel: a few
short bullets per version, in plain words for players, saying what they'll
notice, then one line thanking, by their Discord name, everyone whose
feedback or report led to the changes (each name once; no line when nobody
asked). Each release PR writes the new version's section here next to its
CHANGELOG.md section, and after the upload `tools/post_general.py` posts it
under a line with the addon's name and version that points players to
#announcements for the full list. No link or addon card goes with it. This
is the only report that names players. A version with no section here posts
nothing in #general.
This file does not ship in the addon, but its newest sections do, without
the thanks line: `python tools/make_whatsnew.py` writes them into
Core/WhatsNewText.lua for the in-game What's New window. Run it after
writing a section; the release check refuses a tag while it is behind.

The window shows new features only. Write a section's features first, then
a "Fixes and changes:" line with the fixes and other changes under it: those
go to Discord but stay out of the window, and a section of only fixes puts
nothing in it. Say what each feature does in a few plain words, the way you'd
tell a friend: no hype, no questions to the reader, no exclamation marks
outside the thanks line, no dashes as punctuation, no "now you can". The
tool prints a note for a shipped line that reads like an advert.

## 1.9.5

Fixes and changes:

- No more frame drops with the profession window open over a long session.

## 1.9.4

Fixes and changes:

- Vendor map pins show the material icon round and clear.

## 1.9.3

Fixes and changes:

- One Window keeps its size when it docks while folded.

## 1.9.2

Fixes and changes:

- Vendor map pins show the icon of the material to buy.

## 1.9.1

Fixes and changes:

- Various bug fixes for Tradeskills.

## 1.8.0

Fixes and changes:

- Added a Snipe tab to the Auction House. Snipe actively scans the AH for items posted under their usual price and alerts you. This is an early build of this feature, and it is off by default. You can turn it on in Settings > Auction House > Snipe Tab:.
- Various bug fixes for Tradeskills.

