# Changelog

Versions follow [semantic versioning](https://semver.org): the middle number
moves for new behaviour, the last for fixes alone.

## Unreleased

Nothing published yet. The addon is in testing on WoW: Forever beta
(interface 16001) and has not had a public release.

Added since the repository was created:

- Listings are verified by reading the auction back rather than waiting for an
  event the client does not reliably fire.
- Item auctions are priced in whole silver, matching the cheapest rival and
  undercutting by a silver only when the sale still clears the minimum profit.
- Prices below vendor value are flagged rather than quietly posted.
- Craft names in the Profit list are coloured by item quality, with a column
  showing what can be made now.
- The reagent bag, and any container past bag 4, counts toward materials.
- Equipped items no longer count as stock.
- Part of a stack can be listed, with a per-item quantity box.
- The database reports which source it was recovered from.
