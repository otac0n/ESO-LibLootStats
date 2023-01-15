# LibLootStats
ESO Addon library to collect stats about containers and nodes that you use.

Depends On:
* LibAddonMenu-2.0
* LibSavedVars

Doesn't Track
* Constructed Items
* Excavation
* Quest Items
* Leads
* Character?
* Long Term
  - Consumed Items (improvement, filling gems, constructed items, quest items, containers, etc.)
  - Improvement (including failure)
  - Track "Gather Nearby Loot" Setting
  - Track Companion levels when looting chests and pickpocketing
  - Track chest difficulty
  - Treasure Map -> Dirt Mound -> Treasure Chest -> Lead (etc.) -> Motif (etc.)
  - Monster Class -> Assasination -> Loot
  - Constructed (mats) -> Improvement (mats) -> Enchant (glyph) -> Use -> Repair (gem) -> Decon (mats)

Known Bugs:
* Looking at another node while looting a Heavy Sack (or similar short lived node) will record the other node as returning the resources.
* Looting an item with a nearly-full inventory can confuse the state machine. (e.g. LootWindow)
* Looting an item when you are near a full stack will break the item into two actions which can prevent recording.
* Purchased mail items are recorded. (OK? Maybe make an option.)
* Auto-completed interaction dialogues may not record the final dialogue option chosen.
* Deconstruction / Refinement which yields one of the items deconstructed (e.g. jewelry grains) will record a negative outcome.

ESOUI page: https://www.esoui.com/downloads/info3477-LibLootStats.html

Addon users: Please submit issues here for visibility to other contributors

Addon authors/contributors: Please make pull requests to add functionality or fix issues.
