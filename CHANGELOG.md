# Klopfer's Item Tracker - TBC Anniversary Edition - Changelog

## v0.6.1

### Documentation

- **README screenshots** — embedded one screenshot per top-level feature (`item_tracking_toasts.png` for loot, `ldb_datatext.png` for session gold, `gear_goals_loadout.png` for GearGoals). Stale screenshots from earlier loot-history / standalone-settings UIs (`loot_history.png`, `loot_history_roll_details.png`, `settings.png`) removed
- **README version row** — corrected to match the addon version (the v0.6.0 release left the README compatibility table at 0.5.2)

## v0.6.0

### New Features

- **Klopfer's Item Tracker rebrand** — TOC title, panel headers, anchor bar, minimap tooltip, and chat output (now prefixed `[KIT]`) all read the new brand. Internal API tags (`"ItemTracker"` listener name on LootReserve, Auctionator query tag) stay for back-compat. New primary slash `/kit`; `/it` and `/itemtracker` are aliases
- **Settings live in the WoW Interface AddOns pane** — the standalone settings window has been retired. Esc → Interface → AddOns → Klopfer's Item Tracker uses the modern `Settings.RegisterAddOnSetting` + `CreateCheckbox` / `CreateSlider` / `CreateDropdown` flow (Molinari-style native widgets). The GearGoals sub-category nests beneath it; phase selector is a row of numbered buttons matching TBCA_BIS
- **Unified loot log** — the legacy "Loot History" pop-out is gone. The LOOT LOG tab inside the Gear Tracker is the single source-of-truth view, with an ALL / WISHLIST scope toggle (default ALL), a quality dropdown, and shared name / player search. Anchor bar, minimap, and LDB clicks all route there
- **GearGoals drop popup animations** — 0.3s alpha fade-in on Show plus a sine-wave alpha pulse on the corner brackets while the popup is awaiting input. Gated by a new `popupAnimations` setting in the GearGoals sub-pane
- **Persistent bank ownership cache** — `ScanBagsForItemID` was only walking carried bags, so items stored in the bank read as TARGET on every login. The bank is now snapshotted into `ItemTrackerCharDB.bankItems` whenever the bank UI is visible (`BANKFRAME_OPENED` + `PLAYERBANKSLOTS_CHANGED` + filtered `BAG_UPDATE`); the snapshot survives logout, `/reload`, and travel away from the banker, so OWNED status is durable

### Improvements

- **Single dark/gold visual identity** — the cyan/glassy palette in the toast bar, anchor bar, and roll panel has been replaced with the same dark/gold palette as the Gear Tracker. Palette + frame helpers live in a new shared `modules/Theme.lua` (`Theme.P`, `SetColor`, `AddBackground`, `AddBorder`); no `BackdropTemplate` calls remain in the addon's code
- **Slash dispatcher trimmed** — every UI-redundant branch (`config`, `options`, `history`, `phase X`, `gear copy`, `gear import bis`, `gear unsourced`, `gear atlasloot-stats`, `reset`) has been removed in favour of UI interactions. What stays is what's actually faster as CLI: `status`, `clear`, `debug`, `version`, and the `test …` simulation harness
- **`/kit test` is discoverable** — bare `/kit test` now prints the menu of available simulators instead of silently firing a random loot toast. Subcommands renamed for clarity: `lc` → `council`, `gear` → `bisdrop`. Unknown subcommands print a friendly hint pointing back at the menu
- **Click bindings rationalised** — minimap left-click toggles the Gear Tracker (LOADOUT default), shift-click jumps to the LOOT LOG tab. LDB DataText left-click toggles the Gear Tracker, shift-click opens LOOT LOG, right-click stays on Reset session. Settings access is exclusively via Esc → Interface → AddOns; the redundant right-click → Settings shortcuts (and their tooltip lines) are gone

### Bug Fixes

- **Toast icons rendered as blank gold squares** — the dark/gold restyle replaced the icon's neutral grey overlay with a solid gold rectangle at near-full alpha sitting on top of the icon. Switched to the iconHolder + AddBorder pattern GearGoalsUI uses, so the icon stays fully visible inside a thin gold frame
- **Bank items dropped to TARGET on bank close** — the close-time rescan was firing 0.2s after `BANKFRAME_CLOSED`, by which point `GetContainerItemLink` returned nil for every bank slot and wiped the cache. `RescanBankToCache` now bails when the bank is closed, and the close-time rescan was dropped (the open-time + slot-change rescans already kept the cache in sync with every move)
- **Settings panel didn't appear in the Interface pane** — TBC Anniversary 2.5.5 silently ignores `InterfaceOptions_AddCategory` registrations. Migrated to `Settings.RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory`, exposing the parent category to GearGoalsConfig so it nests as a `Settings.RegisterCanvasLayoutSubcategory` underneath

---

## v0.5.2

### Bug Fixes

- **Roll panels overlap when multiple items are rolled** — when two or more roll toasts were active simultaneously, their right-side roll panels overlapped because the toast height stayed at the base 52px while the roll panel could be taller (up to 78px for 5 entries); toast height now grows to match the roll panel, so stacked toasts leave enough vertical space

---

## v0.5.1

### Bug Fixes

- **Game freeze on last boss loot** — `CreateLootToast` had an infinite `while` loop: when max visible toasts was reached, `fadeOut:Play()` was async and never reduced the count, spinning forever and freezing the client; now immediately releases oldest toasts
- **Duplicate toasts and history entries for rolled items** — after a roll finished, the subsequent "receives loot" chat message bypassed the active-roll filter (only checked unfinished rolls) and created a second toast and history entry; now includes recently-finished rolls in the filter
- **Event bus error isolation** — a Lua error in one event subscriber (custom or WoW) no longer breaks the entire event chain; both `EventBus:Fire()` and the WoW event dispatcher now wrap callbacks in `pcall`

### Improvements

- **RollTracker rewritten to use `C_LootHistory` API** — replaced fragile locale-dependent chat message parsing with structured WoW API calls; `LOOT_HISTORY_ROLL_CHANGED` for individual roll updates, `LOOT_ROLLS_COMPLETE` / `LOOT_HISTORY_ROLL_COMPLETE` for definitive winner detection; eliminates all regex patterns and the `CANCEL_LOOT_ROLL` grace period hack
- **Safety timeout via `GetLootRollTimeLeft` polling** — replaces the 5-second `CANCEL_LOOT_ROLL` delay; polls only while rolls are active, finishes stuck rolls after a 3-second grace period
- **Pre-populated rolls shown on toast creation** — roll toasts now display pre-existing roll entries (e.g. LootReserve reserves) immediately, instead of waiting for the next `ROLL_UPDATE`

---

## v0.5.0

### New Features

- **Gold/hr tracking** — tracks session value of all looted items (vendor price via `GetItemInfo`, AH price via Auctionator if installed); grey vendor trash and quest gold rewards included
- **LDB Data Broker** — creates a `"ItemTracker Gold"` data source via LibDataBroker; works with ElvUI DataTexts, Titan Panel, or any LDB display; main text shows combined gold/hr (raw + vendor); tooltip breaks down raw gold, vendor value, and AH value with per-hour rates and session totals; left-click opens history, shift-click opens config, right-click resets session

### Bug Fixes

- **Roll results missing player names** — `CANCEL_LOOT_ROLL` fired the moment the player clicked Need/Greed/Pass (closing their roll frame), immediately finishing the roll before result messages arrived; added a 5-second grace period so chat messages populate the rolls array
- **Roll capture order broken on some clients** — pattern captures were assigned by position, which broke when `%d` appeared before `%s` in the format string; now identifies captures by content (pure digits → number, `|H` → item link, remainder → player name)
- **LootReserve infinite retry freeze** — `OnRequestRoll` retried `GetItemInfo` every 0.5s with no limit when an item wasn't cached; capped at 5 retries

### Improvements

- **Shared FormatCopper utility** — `IT:FormatCopper()` replaces duplicated local functions across Core, Toast, and UI modules
- **Positional format specifiers** — `FormatToPattern` now handles `%1$s`, `%2$d` style specifiers for localized global strings

---

## v0.4.3

### Bug Fixes

- **Session gold and history not showing on open** — `RefreshHistory()` was called before `historyFrame:Show()`, causing the `IsShown()` guard to bail out; swapped order so content renders on first open

---

## v0.4.2

### Bug Fixes

- **History icon border colored by quality** — loot history rows used a quality-colored overlay on the icon border, inconsistent with toasts which use a neutral border; now both use the same neutral style

---

## v0.4.1

### Bug Fixes

- **RCLootCouncil integration not activating** — addon lookup used wrong AceAddon name (`"RCLootCouncil"` instead of `"RCLootCouncil_Classic"`), causing all hooks to silently fail
- **RCLC toasts stuck forever** — VotingFrame comms only fire for council/observer players; non-council raiders never received award notifications, causing toasts to accumulate indefinitely; fixed with multi-layer detection:
  - `ITEM_LOOTED` fallback matches distributed items to active sessions
  - 2-second polling timer checks RCLC's loot table for `awarded` field
  - 3-minute safety timeout auto-finishes stuck sessions regardless
- **Duplicate toasts on RCLC award** — loot toast appeared alongside the existing roll toast when the item was distributed; now suppressed for active RCLC sessions

### Improvements

- **RCLC response tracking** — council votes (Mainspec, Offspec, Minor Upgrade, Pass) now appear in the roll panel with RCLC's own colored response text
- **Early-return guard** — `OnLootTableReceived` hook now skips RCLC's internal retry/reschedule calls

---

## v0.4.0

### New Features

- **Live roll ranking panel** — roll toasts now show a sorted side panel to the right, ranking rollers from highest to lowest (top 5 visible), with passes grouped at the bottom; panel persists through winner announcement until the toast fades
- **Configurable chat output** — new "Show chat messages" toggle in settings; when disabled, all addon chat messages are suppressed (toast-only mode)
- **Neutral icon border** — removed quality-colored rectangle behind the toast icon; item quality is now conveyed solely through colored item name text

### Improvements

- **Test roll expanded** — `/it test roll` now simulates 15 players with random roll types (need/greed/pass/disenchant) for realistic testing
- **Roll update fix** — roll display now updates correctly for test, RCLootCouncil, and LootReserve rolls (fallback to toast-stored rollData)

---

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
