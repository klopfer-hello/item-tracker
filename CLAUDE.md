# Klopfer's Item Tracker - CLAUDE.md

## Project Overview

**Klopfer's Item Tracker** is a World of Warcraft addon for **TBC Classic Anniversary** (interface version 20504/20505, game version 2.5.5). It bundles three big features behind a single addon:

1. **Loot tracking** — toast notifications for looted items, group/raid roll tracking, RCLootCouncil + LootReserve integration, scrollable history panel.
2. **Session gold** — running gold/hr rate with vendor and Auctionator AH valuation, optional LDB DataText.
3. **GearGoals** — character-scoped, spec-aware, phase-organised BiS / loadout tracker with drop-alert popups, AtlasLoot source labels, and tier-set token redemption.

The folder is still named `ItemTracker` (and the SavedVariables key is still `ItemTrackerDB`) for backwards compatibility — only the user-facing branding changed. The addon uses a global namespace `IT` (also `ItemTracker`) populated via the addon vararg `local ADDON_NAME, IT = ...`. Chat output is prefixed `[KIT]`. Slash commands: `/kit` (primary), `/it` and `/itemtracker` kept as aliases. The dispatcher itself is intentionally minimal — most interaction is through the UI; the CLI keeps only `status`, `clear`, `debug`, `version`, and the `test …` simulation harness.

## Features

- **Toast Notifications** — pop-up cards for looted items, sliding from a movable anchor bar (direction configurable)
- **Solo & Group Loot** — separate configurable quality thresholds (Poor through Legendary)
- **Roll Tracking** — tracks Need/Greed/Pass/Disenchant rolls in real time; toast persists until winner is chosen
- **RCLootCouncil Integration** — detects loot council sessions, shows items being voted on, finalizes when awarded
- **LootReserve Integration** — tracks soft reserves, shows roll requests, announces winners
- **Loot History** — standalone pop-out window with item tooltips, roll details, and filters (name/player search, quality dropdown)
- **Quest Reward Tracking** — detects items from quest NPCs via `QUEST_LOOT_RECEIVED` and `LOOT_ITEM_PUSHED_SELF` fallback
- **Gold Tracking** — session gold total displayed in history header (not persisted); gold/hr rates with vendor and AH item valuation
- **LDB Data Broker** — session gold display via LibDataBroker; works with ElvUI DataTexts, Titan Panel, or any LDB display; tooltip shows vendor/AH totals and gold/hr rates; left-click history, shift-click config, right-click reset
- **Movable Anchor Bar** — thin glassy strip; toasts stack above or below; drag to reposition; hides when locked but reveals on hover
- **Minimap Button** — "?" icon, draggable around minimap edge; left-click toggle, shift-click history, right-click config
- **Blizzard Integration** — appears in Interface → AddOns settings panel

## Architecture

Follows **SOLID** principles adapted to Lua/WoW:

| Principle | Application |
|---|---|
| **Single Responsibility** | Each module handles exactly one concern |
| **Open/Closed** | Modules extend behaviour by subscribing to events; Core doesn't change when modules are added |
| **Liskov Substitution** | N/A (no inheritance hierarchy) |
| **Interface Segregation** | Modules expose small, focused public APIs; internal state stays local |
| **Dependency Inversion** | Modules depend on the event bus abstraction, not on each other directly |

### Data Flow

```
WoW Events
    │
    ├─ CHAT_MSG_LOOT ────────→ LootDetector ──→ fires ITEM_LOOTED
    ├─ QUEST_LOOT_RECEIVED ──→ LootDetector ──→ fires ITEM_LOOTED
    ├─ CHAT_MSG_SYSTEM ──────→ LootDetector ──→ fires ITEM_LOOTED (pushed items)
    ├─ CHAT_MSG_MONEY ───────→ LootDetector ──→ fires GOLD_LOOTED
    │
    ├─ START_LOOT_ROLL ──────────→ RollTracker ──→ fires ROLL_STARTED
    ├─ LOOT_HISTORY_ROLL_CHANGED → RollTracker ──→ fires ROLL_UPDATE
    ├─ LOOT_ROLLS_COMPLETE ──────→ RollTracker ──→ fires ROLL_ENDED
    │
    ├─ RC:OnLootTableReceived → RCLCIntegration → fires ROLL_STARTED / ROLL_ENDED
    ├─ LR RequestRoll/Winner ─→ LRIntegration ──→ fires ROLL_STARTED / ROLL_ENDED
    │
    ▼
                    ┌─────────────────┐
                    │   Event Bus      │
                    └──┬──────┬───────┘
                       │      │
              ┌────────┘      └──────────────┐
              ▼                               ▼
         LootHistory              ┌──── Toast (UI)
         (SavedVars)              │     (notifications)
              │                   │
              ▼                   ▼
         UI (history)        GoldTracker ──→ ElvUIDataText
                            (vendor/AH/hr)   (ElvUI panel)
```

## File Structure

| File | Purpose |
|---|---|
| [Core.lua](Core.lua) | Framework: event bus, WoW event registration API, SavedVariables, utilities, slash commands, test harness |
| [modules/LootDetector.lua](modules/LootDetector.lua) | Parses `CHAT_MSG_LOOT`, `QUEST_LOOT_RECEIVED`, `CHAT_MSG_SYSTEM` (pushed items), `CHAT_MSG_MONEY`; fires `ITEM_LOOTED` and `GOLD_LOOTED` |
| [modules/RollTracker.lua](modules/RollTracker.lua) | Tracks rolls via `START_LOOT_ROLL`, `C_LootHistory` API, and `LOOT_ROLLS_COMPLETE`; fires `ROLL_STARTED`/`ROLL_UPDATE`/`ROLL_ENDED`; safety timeout via `GetLootRollTimeLeft` polling |
| [modules/LootHistory.lua](modules/LootHistory.lua) | Stores loot entries in SavedVariables, enforces size limits, fires `HISTORY_UPDATED` |
| [modules/RCLCIntegration.lua](modules/RCLCIntegration.lua) | Hooks RCLootCouncil: `OnLootTableReceived` → ROLL_STARTED, `OnAwardedReceived` → ROLL_ENDED |
| [modules/LRIntegration.lua](modules/LRIntegration.lua) | Hooks LootReserve: `RequestRoll` handler → ROLL_STARTED, `SendWinner` handler → ROLL_ENDED; tracks reserves via `RegisterListener` |
| [modules/GoldTracker.lua](modules/GoldTracker.lua) | Session gold/hr tracking: accumulates vendor value (`GetItemInfo` sellPrice) and AH value (Auctionator API) for self-looted items; fires `GOLD_RATES_UPDATED` |
| [modules/ElvUIDataText.lua](modules/ElvUIDataText.lua) | LDB (LibDataBroker) data source: session gold display, tooltip with vendor/AH breakdown and gold/hr rates, click handlers for history/config/reset; works with ElvUI, Titan Panel, or any LDB display; safe if LDB not available |
| [modules/Toast.lua](modules/Toast.lua) | Creates/animates toast pop-ups, manages stacking (up or down), shows live sorted roll ranking in a right-side panel (top 5), neutral icon border with quality-colored text |
| [modules/UI.lua](modules/UI.lua) | Movable anchor bar (hides on lock, reveals on hover) + standalone history pop-out with name/quality filters and session gold display |
| [modules/Config.lua](modules/Config.lua) | Settings panel (standalone + InterfaceOptions), quality dropdowns, sliders, checkboxes |
| [modules/Minimap.lua](modules/Minimap.lua) | Minimap "?" button, draggable around edge, left-click toggle / shift-click history / right-click config |

## Custom Events (Event Bus)

| Event | Payload | Fired by |
|---|---|---|
| `ITEM_LOOTED` | `{ itemLink, itemID, quality, count, player, isSelf, isGroupLoot, timestamp, icon }` | LootDetector |
| `ITEM_VALUE` | same as `ITEM_LOOTED` but fires for all self-looted items regardless of quality threshold | LootDetector |
| `GOLD_LOOTED` | `sessionCopper` (number) | LootDetector |
| `ROLL_STARTED` | `rollData` table | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_UPDATE` | `rollID, { player, rollType, number }` | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_ENDED` | `rollData` table (with `winner`, `rolls`, `finished`, `source` fields) | RollTracker, RCLCIntegration, LRIntegration |
| `GOLD_RATES_UPDATED` | (none) | GoldTracker |
| `HISTORY_UPDATED` | (none) | LootHistory |
| `PLAYER_READY` | (none) | Core |
| `PLAYER_LOGOUT` | (none) | Core |

## SavedVariables Schema

### `ItemTrackerDB` (global)
```lua
{
    settings = {
        enabled               = true,
        soloQualityThreshold  = 2,   -- 0=Poor .. 5=Legendary
        groupQualityThreshold = 2,
        toastDuration         = 8,   -- seconds
        toastMaxVisible       = 5,
        toastUpward           = true, -- true = up, false = down
        historySize           = 100,
        locked                = false, -- hides bar when true, reveals on hover
        position              = nil,   -- { point, relativePoint, x, y }
        minimapAngle          = 225,
        showMinimap           = true,
        chatOutput            = true,  -- print messages to chat frame
    },
    history = {
        -- ordered newest-first; each entry:
        -- { itemLink, itemID, quality, count, icon, player, isSelf,
        --   isGroupLoot, timestamp, wasRolled, rolls, winner }
    },
}
```

### `ItemTrackerCharDB` (per-character)
Currently unused; reserved for future per-character overrides.

## External Addon Integration

### RCLootCouncil (`modules/RCLCIntegration.lua`)
- Detects `RCLootCouncil_Classic` or `RCLootCouncil` via `IsAddOnLoaded`
- Gets addon reference via `LibStub("AceAddon-3.0"):GetAddon()` — tries `"RCLootCouncil_Classic"` first, then `"RCLootCouncil"`
- Hooks `RC:OnLootTableReceived()` (fires on all clients) → `ROLL_STARTED` per session item; guarded by `rc.enabled` and `entry.link` checks to skip RCLC's internal retry/reschedule calls
- Hooks `VF:OnResponseReceived()` on the voting frame module → `ROLL_UPDATE` with RCLC colored response text (council members only)
- Hooks `VF:OnAwardedReceived()` on the voting frame module → `ROLL_ENDED` with winner (council members only)
- Subscribes to `ITEM_LOOTED` as fallback award detection — non-council players don't receive VotingFrame comms, so matching looted items to active sessions ends the roll toast
- Runs a 2-second polling timer that checks RCLC's `GetLootTable()` for the `awarded` field (set for council/observer clients)
- 3-minute safety timeout auto-finishes any session that wasn't resolved by other detection paths
- Registers `RCMLAwardSuccess` message (ML client bonus) and `RCSessionEnd` (cleanup)
- Uses rollID range 100000+ to avoid collisions with native rolls

### LootReserve (`modules/LRIntegration.lua`)
- Detects `LootReserve` via `IsAddOnLoaded`
- Registers reserve listener via `LootReserve:RegisterListener("RESERVES", "ItemTracker", callback)`
- Wraps `LootReserve.Comm.Handlers[12]` (RequestRoll opcode) → `ROLL_STARTED` with reserve info
- Wraps `LootReserve.Comm.Handlers[19]` (SendWinner opcode) → `ROLL_ENDED` with winner
- Uses rollID range 200000+ to avoid collisions

### Auctionator (`modules/GoldTracker.lua`)
- Detects `Auctionator.API.v1.GetAuctionPriceByItemID` at runtime
- Queries AH prices per looted item via `Auctionator.API.v1.GetAuctionPriceByItemID("ItemTracker", itemID)`
- Returns copper value or nil; nil falls back to vendor price
- Non-BoP items only (BoP items use vendor price for both columns)

### LibDataBroker / ElvUI (`modules/ElvUIDataText.lua`)
- Gets `LibDataBroker-1.1` via `LibStub` (provided by ElvUI_Libraries and many other addons)
- Creates LDB data source `"ItemTracker Gold"` with `type = "data source"`
- Any LDB display (ElvUI DataTexts, Titan Panel, ChocolateBar) auto-discovers it
- ElvUI shows it as `"LDB: ItemTracker Gold"` in DataText config
- Updates text via `GOLD_RATES_UPDATED` event subscription

All integrations are safe — they do nothing if the external addon is not installed, and all hooks are wrapped in `pcall`.

## Game Version Notes (Critical)

- **TBC Classic Anniversary uses the `C_Container` namespace** — legacy globals may not exist.
- A compatibility shim in [Core.lua](Core.lua) maps legacy globals to `C_Container` equivalents.
- `C_Container.GetContainerItemInfo` returns a **table** — the shim wraps it to return legacy multiple-return-value style.
- **`UNIT_SPELLCAST_*` event signature**: TBC Classic Anniversary uses `(unit, castGUID, spellID)` 3-arg format.
- `C_Timer.After(delay, func)` is available.
- Item links follow pattern `item:(%d+)` for extracting itemID.
- **`QUEST_LOOT_RECEIVED(questID, itemLink, count)`** — fires when quest reward items are received from NPCs.
- **`LOOT_ITEM_PUSHED_SELF`** — Blizzard global string for items pushed to bags; used as fallback for quest rewards.
- `InterfaceOptions_AddCategory(panel)` may not exist; guarded with existence check.
- **`C_LootHistory`** namespace is available — `GetItem()`, `GetPlayerInfo()`, `GetNumItems()` work; `LOOT_HISTORY_ROLL_CHANGED` and `LOOT_ROLLS_COMPLETE` events fire correctly.
- **`GetLootRollTimeLeft(rollID)`** is available — returns seconds remaining (0 when expired); wrapped in `pcall` for safety.

## Coding Conventions

- Module pattern: `local ModName = {}; IT.ModuleName = ModName`
- Debug logging: `IT:Debug("message")`
- Settings access: `IT.db.settings.<key>` (persisted SavedVariables)
- WoW event registration: `IT:RegisterEvent("EVENT_NAME", callback)` in module `Initialize()`
- Custom events via bus: `IT.Events:Subscribe("EVENT", callback)` / `IT.Events:Fire("EVENT", ...)`
- Module initialization wrapped in `pcall` — one failing module doesn't break others
- Locale-safe message parsing via `IT:FormatToPattern(globalString)` helper
- UI controls use `AddThinBorder()` helper and custom-drawn tracks (no BackdropTemplate on sliders)

## Planned: GearGoals Module

A character-scoped, spec-aware, phase-organised BiS / loadout tracker integrated **as a module set inside ItemTracker** (originally scoped as a standalone addon `KlopfersGearTracker`, merged here to reuse `LootDetector`, `IT:FormatToPattern`, the event bus, the toast system, and the minimap button).

### Concepts

- **Phase** ∈ `{ "pre-raid", "1", "2", "3", "3.5", "4" }`. String key (because of `"3.5"`); display order enforced by an ordered list in code.
- **Spec** auto-derived per character via `GetTalentTabInfo` — tree with the most points wins. `specKey = "<CLASS>-<TreeName>"` (e.g. `"DRUID-Restoration"`). Resolves automatically on respec; no manual override in MVP.
- **Slot** = inventory slot ID, the same 17 slots tracked elsewhere (no shirt/tabard).
- **Goal** = `{ itemID, rank, obtained, note }`. Ordered list of picks per slot; rank 1 = preferred.
- **Source data** = `{ boss, raid }` strings shown under each item; pulled from `AtlasLootClassic_TBCA_BIS` at runtime (safe fallback to a manual entry field if not loaded).

### Behaviour

- **Notification scope**: only goals from the **current phase** notify, *plus* pre-raid (sticky — pre-raid goals always notify regardless of selected phase).
- **Rank suppression**: if the slot is currently equipped with a goal item of rank N, suppress notifications for all ranks ≥ N in that slot. Equipping a rank-1 goal silences the slot entirely.
- **Cross-phase carryover**: explicit per-phase, no auto-copy. A "Copy from previous phase" button is offered in the UI as a one-shot action.
- **Detection sources**: `ITEM_LOOTED` from `LootDetector` (group/raid/solo loot already locale-safe) **plus** a chat-link scanner over `CHAT_MSG_RAID/RAID_LEADER/PARTY/PARTY_LEADER/WHISPER/WHISPER_INFORM` matching `item:(%d+)` against the active goal set.
- **Dedup ("once per drop")**: in-memory `Set<itemID>` keyed by itemID, *not persisted*. Cleared on:
  - leaving the group (`IsInGroup()` transitions to false), or
  - changing instances/zones (`PLAYER_ENTERING_WORLD`).
  Rule: a corpse-sighting (own loot list / `ITEM_LOOTED`) suppresses all subsequent chat-link mentions of the same itemID within the current dedup scope.
- **Tooltip line**: `On your <SpecLabel> list (P3, rank 1)` for the active spec, dimmed line for other specs that have it, strike-through with `(have)` when `obtained=true`.

### UI

Top-level window has tabs: **LOADOUT / RAIDS / LOOT LOG** (WISHLIST omitted per design review).

- **LOADOUT** — phase-tab subnav (P1 / P2 / P3 / P3.5 / P4 / pre-raid). Sidebar with phase summary, slots filled, avg ilvl, status breakdown (Owned / Targeted / Locked), phase actions (Copy from previous, Import, Export to /share). Main pane: filter bar + per-slot card with ranked picks. Each pick row: rank badge, icon, quality-coloured name, `boss · raid`, ilvl, status pill (`TARGET` / `OWNED` / `EQUIPPED` / `LOCKED`).
- **RAIDS** — same data pivoted by raid instance.
- **LOOT LOG** — re-uses `LootHistory` filtered to entries that match a goal.
- **Spec switcher** — dropdown next to the spec name in the header; lets the user view/edit other specs' loadouts on the same character.
- **Search** — click-to-focus filter input above the slot list. No global keybind in MVP.
- **Theme** — dark only in MVP; light theme deferred.

### Drop Alert popup

Movable, centered by default. Header line `· PHASE 3 · PICK #1 FROM YOUR LIST ·`, big "IT HAS BEGUN" title, item card with rank corner-badge, three meta cells (`PHASE` / `PICK` / `LOOTED BY`), action buttons.

Buttons depend on which list the item is on:

| Match | Buttons |
|---|---|
| Main spec list only | `ROLL 100 · MS` |
| Off spec list only  | `ROLL 99 · OS` |
| Both spec lists     | `ROLL 100 · MS` and `ROLL 99 · OS` side by side |

Rolls are issued via `RandomRoll(100, 100)` / `RandomRoll(99, 99)`. No automatic roll — the player picks. **Mark Seen** and **Snooze** are not in MVP.

### SavedVariables additions

`ItemTrackerCharDB` (currently unused) becomes the home for goals:

```lua
ItemTrackerCharDB.goals = {
    [specKey] = {                         -- e.g. "DRUID-Restoration"
        [phase] = {                       -- e.g. "3"
            [slotID] = {
                { itemID = 30183, rank = 1, obtained = false, note = "..." },
                { itemID = 28744, rank = 2, obtained = false },
            },
        },
    },
}
```

`ItemTrackerDB.settings.gearGoals`:

```lua
{
    currentPhase = "pre-raid",   -- account-wide selection
    notifySound  = true,
    popupAnchor  = nil,           -- { point, relativePoint, x, y }
}
```

### External integration: AtlasLootClassic_TBCA_BIS

- Detected via `IsAddOnLoaded("AtlasLootClassic_TBCA_BIS")`, all reads guarded by `pcall`.
- Used as the source-of-truth for `boss · raid` strings when adding an item by ID.
- Manual entry fields remain in the add/edit dialog as fallback when the dependency isn't installed or doesn't have data for an itemID.
- Exact table layout to be inspected at implementation time and isolated in a single reader module.

### Custom events (planned)

| Event | Payload |
|---|---|
| `GEAR_GOAL_DROPPED`        | `{ itemID, itemLink, slot, rank, specKey, phase, source, looter, fromChat }` |
| `GEAR_GOAL_LIST_CHANGED`   | `{ specKey, phase }` |
| `GEAR_GOALS_PHASE_CHANGED` | `{ phase }` |
| `GEAR_GOALS_SPEC_CHANGED`  | `{ specKey }` |

### Module layout (planned)

| File | Purpose |
|---|---|
| `modules/GearGoals.lua`         | Storage, spec auto-detection, goal CRUD, equipped scan, rank-suppression logic, dedup state |
| `modules/GearGoalsDetector.lua` | Subscribes to `ITEM_LOOTED`; chat-link scanner over party/raid/whisper channels; fires `GEAR_GOAL_DROPPED` |
| `modules/GearGoalsAlert.lua`    | Drop popup UI |
| `modules/GearGoalsUI.lua`       | Main window: top tabs, phase tabs, sidebar, slot grid, add/edit dialog |
| `modules/GearGoalsTooltip.lua`  | `GameTooltip:HookScript("OnTooltipSetItem")` integration |
| `modules/GearGoalsAtlasLoot.lua`| `AtlasLootClassic_TBCA_BIS` reader, no-op when the dep is missing |

### MVP / Polish slicing

**MVP** (first ship):
- Phase tabs (LOADOUT only — RAIDS / LOOT LOG tabs deferred)
- Slot grid with ranked picks per phase
- Add / edit / delete goal (item by name → resolves via `GetItemInfo`, queued retry on `GET_ITEM_INFO_RECEIVED`)
- AtlasLoot autofill for `boss · raid` if available, manual fields otherwise
- Drop popup with MS / OS roll buttons
- Tooltip integration with phase + rank line
- Per-spec auto-detection + spec switcher dropdown

**Polish** (later passes):
- RAIDS tab
- LOOT LOG tab
- Status breakdown sidebar + avg ilvl + slots-filled bar
- Phase actions: Copy from previous phase, Import BiS list, Export to /share
- Search filter
- Light theme
- Polished popup typography / animations

### Open / TBD at implementation time

- AtlasLoot table layout — exact paths to inspect at impl time, isolated in `GearGoalsAtlasLoot.lua`.
- Active row indicator colour for "currently equipped" goal.
- Chat-link scanner: which channels by default, which configurable.
- Whether `obtained=true` is set automatically on first `ITEM_LOOTED` to that character (probably yes, as a UX shortcut), or must be flipped manually.

## Reference Addon: FishingKit

FishingKit is located at `d:\Games\World of Warcraft\_anniversary_\Interface\AddOns\FishingKit`. It serves as a reference for TBC Classic API usage, coding conventions, and addon structure patterns.

## Versioning

This project follows **Semantic Versioning** (`MAJOR.MINOR.PATCH`):

| Change type | Version bump |
|---|---|
| Breaking changes (SavedVariables schema incompatible, removed features) | MAJOR |
| New features (backwards-compatible) | MINOR |
| Bug fixes only (no new features) | PATCH |

### Beta Releases
Beta releases use `MAJOR.MINOR.PATCH-beta.N`.

## Release Process

### Stable release
Update all four in a single commit, then tag:
1. **`CLAUDE.md`** — architecture, file structure, events, schema
2. **`CHANGELOG.md`** — new `## vX.Y.Z` section at top
3. **`README.md`** — version badge, feature list
4. **`ItemTracker.toc`** — bump `## Version:`

```
git add CLAUDE.md CHANGELOG.md README.md ItemTracker.toc
git commit -m "chore: release vX.Y.Z"
git tag -a vX.Y.Z -m "vX.Y.Z"
```

### Beta release
1. **`CHANGELOG.md`** — `## vX.Y.Z-beta.N`
2. **`ItemTracker.toc`** — `## Version: X.Y.Z-beta.N`

```
git add CHANGELOG.md ItemTracker.toc
git commit -m "chore: release vX.Y.Z-beta.N"
git tag -a vX.Y.Z-beta.N -m "vX.Y.Z-beta.N"
```
