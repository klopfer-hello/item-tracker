# ItemTracker - TBC Anniversary Edition - Changelog

## v0.1.0

### Initial Release

- **Toast Notifications** — Windows Action Center-style pop-ups for looted items with quality-colored icon borders, fade-in/out animations, and configurable duration
- **Solo Loot Tracking** — detects items via locale-safe `CHAT_MSG_LOOT` parsing
- **Group / Raid Loot Tracking** — shows items looted by all group or raid members
- **Separate Quality Thresholds** — independently configurable minimum quality for solo (default: Uncommon) and group/raid (default: Uncommon)
- **Native Roll Tracking** — tracks Need/Greed/Pass/Disenchant rolls in real time; toast persists and updates as rolls come in; finalizes when winner is chosen
- **RCLootCouncil Integration** — hooks into loot council sessions via `OnLootTableReceived` and `OnAwardedReceived`; shows items being voted on with "Loot Council in progress..." status; safe when not installed
- **LootReserve Integration** — hooks into soft reserve rolls via `RequestRoll` and `SendWinner` opcode handlers; tracks reserves via `RegisterListener` API; safe when not installed
- **Quest Reward Tracking** — detects items from quest NPCs via `QUEST_LOOT_RECEIVED` event with `LOOT_ITEM_PUSHED_SELF` fallback
- **Gold Tracking** — session gold total parsed from `CHAT_MSG_MONEY` (locale-safe) and displayed in the history panel header; resets each session
- **Loot History** — standalone draggable pop-out window with scrollable item list, item tooltips with roll breakdown on hover, name/player text search filter, and quality dropdown filter (All/Uncommon+/Rare+/Epic+/Legendary)
- **Configurable Toast Direction** — toasts stack upward (default) or downward from the anchor bar
- **Movable Anchor Bar** — thin glassy strip that toasts stack from; drag to reposition; hides when locked but reveals on mouse hover to allow history access
- **Minimap Button** — "?" icon draggable around minimap edge; left-click toggles window, shift-click opens history, right-click opens settings
- **Settings Panel** — standalone config window with quality dropdowns, toast duration/count sliders, history size slider, lock/minimap/direction toggles; also registered in Interface > AddOns via `InterfaceOptions_AddCategory`
- **Test Harness** — `/it test`, `/it test roll`, `/it test lc`, `/it test reserve` for simulating loot scenarios without actual looting
- **Glassy Transparent Design** — dark semi-transparent backgrounds, thin cyan-accented borders, muted labels, quality-colored highlights; matches FishingKit visual style

### Files

- `Core.lua` — Framework, event bus, WoW event registration API, SavedVariables, utilities, slash commands, test harness
- `modules/LootDetector.lua` — Loot/quest/gold detection
- `modules/RollTracker.lua` — Native Need/Greed/Pass roll tracking
- `modules/LootHistory.lua` — History data persistence and management
- `modules/RCLCIntegration.lua` — RCLootCouncil integration
- `modules/LRIntegration.lua` — LootReserve integration
- `modules/Toast.lua` — Toast notification UI
- `modules/UI.lua` — Anchor bar and history pop-out window
- `modules/Config.lua` — Settings panel
- `modules/Minimap.lua` — Minimap button
