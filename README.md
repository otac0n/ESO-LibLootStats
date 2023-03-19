# LibLootStats
ESO Addon library to collect stats about containers and nodes that you use.

Depends On:
* LibAddonMenu-2.0
* LibSavedVars

Doesn't Track
* Constructed Items
* Quest Items (partial)
* Crown Crates and Many Crown or Character Bound Items
* Character, Race, Date/Time
* Leveling Rewards
* Track
  - Trades
  - Sales
    - How to track currencies?
* Ignore
  - Retrieve from House
* Long Term
  - Consumed Items (treasure map?, improvement mats, filling gems, constructed item from mats, quest items, containers, etc.)
  - Treasure Map -> Dirt Mound -> Treasure Chest
  - Monster Class -> Assasination -> Loot
  - Laundered -> Clean
  - Improvement (including failure)
  - Track "Gather Nearby Loot" Setting
  - Track Active Companion and their Unlockable levels when looting chests, pickpocketing, looting alchemy, etc.
  - Constructed (mats) -> Improvement (mats) -> Enchant (glyph) -> Bind -> Use -> Repair (gem) -> Decon (mats)

Known Bugs:
* Looking at another node while looting a Heavy Sack (or similar short lived node) will record the other node as returning the resources.
  - From Harvester: GetInteractionType() == INTERACTION_HARVEST and IsPlayerInteractingWithObject()
  - From VotansHarvester: IsPlayerInteractingWithObject() or IsInteractionPending() and not IsPlayerMoving()
* Looting an item with a nearly-full inventory can confuse the state machine. (e.g. LootWindow)
  - GetInteractionType() == INTERACTION_LOOT, GetLootTargetInfo()
* Looting an item when you are near a full stack will break the item into two actions which can prevent recording.
* Purchased mail items are recorded. (OK? Maybe make an option.)
  - Player Mail items are not recorded.
* Auto-completed interaction dialogues may not record the final dialogue option chosen.
* Deconstruction / Refinement which yields one of the items deconstructed (e.g. jewelry grains) will record a negative outcome.

ESOUI page: https://www.esoui.com/downloads/info3477-LibLootStats.html

Addon users: Please submit issues here for visibility to other contributors

Addon authors/contributors: Please make pull requests to add functionality or fix issues.
