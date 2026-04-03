# ItemTracker - TBC Anniversary Edition - Changelog

## v0.3.1

### Bug Fixes

- **Sliders not draggable** — native WoW `Slider` frame doesn't accept mouse drag in TBC Classic Anniversary; replaced with manual mouse input (click + drag on track area, value calculated from cursor position)

### Documentation

- Updated screenshots (toasts, roll details, settings panel)

---

## v0.3.0

### New Features

- **Gold loot toasts** — configurable toast notification for each gold drop, with coin icon and amount; off by default, enable in settings ("Show gold loot toasts")
- **Toast direction dropdown** — replaced checkbox with a proper Upward/Downward select dropdown

### Improvements

- **Lightened color palette** — toast, bar, and history backgrounds slightly lighter and more transparent for a less heavy look
- **Generic dropdown builder** — `CreateDropdown` extracted from quality dropdown, reusable for any select control

### Bug Fixes

- **Gold toast never appeared** — test helper only fired `GOLD_LOOTED` (history update) but not `GOLD_DROP` (toast trigger)
- **Test gold didn't accumulate** — display now shows both drop amount and cumulative session total

### Files Modified

- `Core.lua` (version, `toastGold` default, `FormatCopper` helper, test gold fix)
- `modules/Toast.lua` (lightened palette, gold toast handler with coin icon)
- `modules/Config.lua` (generic `CreateDropdown`, direction dropdown, gold toast checkbox)
- `modules/LootDetector.lua` (`GOLD_DROP` event, test helper fires both events)
- `modules/UI.lua` (lightened bar/history colors)

---

## v0.2.1

### Documentation

- Added MIT license
- Added screenshots to README (toast notifications, loot history, roll details, settings panel)
- README now includes visual feature walkthrough with inline images

---

## v0.2.0

### Improvements

- **Minimap & addon icon** — replaced placeholder "?" with spyglass icon (`INV_Misc_Spyglass_03`); added `## IconTexture` to TOC for addon list display
- **Gold tracking fixed** — money parsing now uses `GOLD_AMOUNT`/`SILVER_AMOUNT`/`COPPER_AMOUNT` format strings (locale-safe); previously used non-existent globals
- **Gold display** — history header shows "Gold this session: Xg Ys Zc"
- **`/it clear` resets gold** — clearing history now also resets the session gold counter
- **Hidden bar hover reveal** — when bar is locked (invisible), hovering over its position reveals it temporarily so history can still be opened
- **Shift-click minimap** — shift+left-click on minimap button opens loot history directly
- **Quest reward tracking** — items from quest NPCs now detected via `QUEST_LOOT_RECEIVED` and `LOOT_ITEM_PUSHED_SELF` fallback
- **RCLootCouncil integration** — hooks into loot council sessions and awards
- **LootReserve integration** — hooks into soft reserve rolls and winners
- **Toast direction** — configurable upward (default) or downward stacking
- **`/it test gold`** — simulate gold drops for testing

### Bug Fixes

- **Gold never tracked** — `GOLD`, `SILVER`, `COPPER` globals don't exist; replaced with `GOLD_AMOUNT`/`SILVER_AMOUNT`/`COPPER_AMOUNT` pattern conversion
- **Quest items not tracked** — `CHAT_MSG_LOOT` doesn't fire for NPC quest rewards; added `QUEST_LOOT_RECEIVED` + `CHAT_MSG_SYSTEM` pushed-item fallback
- **Module init crash blocked minimap** — one failing module prevented all subsequent modules from loading; wrapped `Initialize()` calls in `pcall`
- **Minimap button invisible** — missing `SetMovable`/`EnableMouse`, wrong icon/border sizing; aligned with FishingKit's proven pattern
- **Config sliders ugly** — replaced `BackdropTemplate` sliders with custom thin-track + invisible native Slider (FishingKit pattern)
- **Dropdown closed immediately** — 1px gap between button and menu caused auto-close; fixed with overlap + grace period
- **History blocked by toasts** — history panel was attached below bar (under toasts); made it a standalone draggable pop-out

### Files Modified

- `Core.lua` (version, `/it clear` gold reset, `/it test gold`, test LC/reserve commands, status command)
- `modules/LootDetector.lua` (gold parsing fix, quest reward detection, pushed item fallback, session gold reset)
- `modules/Toast.lua` (configurable direction, source labels for council/reserve)
- `modules/UI.lua` (standalone history pop-out, filters, gold display, hover reveal, lock state)
- `modules/Config.lua` (rewritten controls, toast direction checkbox, lock calls UI update, guarded InterfaceOptions)
- `modules/Minimap.lua` (spyglass icon, proper sizing, shift-click history)
- `modules/RCLCIntegration.lua` (new)
- `modules/LRIntegration.lua` (new)
- `ItemTracker.toc` (IconTexture, integration modules)

---

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
