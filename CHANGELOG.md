# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone.

## 0.1.0

First public release, for WoW: Forever (interface 16001).

- Lists every recipe you know with its material cost, sell price and profit
  after the auction house cut and deposit, best earners first.
- Counts an intermediate material, like a bolt of cloth, at whichever is
  cheaper: buying it or crafting it.
- Leaves crafts that bind on pickup off the list, since they cannot be sold.
- Craft queue, with a pane beside the profession window and a Gather list of
  the materials still missing.
- Posts to the auction house, matching the cheapest other seller in whole
  silver and undercutting only when the sale still clears your minimum profit.
- Shows sell prices in the profession window and on item tooltips, and marks
  crafts that still give skill points.
- Sales tab records what sold and what came back, read from your mailbox.
