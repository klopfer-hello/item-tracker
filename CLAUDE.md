# ItemTracker - CLAUDE.md

## Project Overview

ItemTracker is a World of Warcraft addon for **TBC Classic Anniversary** (interface version 20504/20505, game version 2.5.5). It provides Windows Action Center-style toast notifications for looted items, group/raid roll tracking, loot council and soft reserve integration, a scrollable loot history panel with filters, and session gold tracking — all in a glassy, transparent design.

The addon uses a global namespace `IT` (also `ItemTracker`) populated via the addon vararg `local ADDON_NAME, IT = ...`.

## Features

- **Toast Notifications** — pop-up cards for looted items, sliding from a movable anchor bar (direction configurable)
- **Solo & Group Loot** — separate configurable quality thresholds (Poor through Legendary)
- **Roll Tracking** — tracks Need/Greed/Pass/Disenchant rolls in real time; toast persists until winner is chosen
- **RCLootCouncil Integration** — detects loot council sessions, shows items being voted on, finalizes when awarded
- **LootReserve Integration** — tracks soft reserves, shows roll requests, announces winners
- **Loot History** — standalone pop-out window with item tooltips, roll details, and filters (name/player search, quality dropdown)
- **Quest Reward Tracking** — detects items from quest NPCs via `QUEST_LOOT_RECEIVED` and `LOOT_ITEM_PUSHED_SELF` fallback
- **Gold Tracking** — session gold total displayed in history header (not persisted)
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
    ├─ START_LOOT_ROLL ──────→ RollTracker ───→ fires ROLL_STARTED / ROLL_UPDATE / ROLL_ENDED
    │
    ├─ RC:OnLootTableReceived → RCLCIntegration → fires ROLL_STARTED / ROLL_ENDED
    ├─ LR RequestRoll/Winner ─→ LRIntegration ──→ fires ROLL_STARTED / ROLL_ENDED
    │
    ▼
                    ┌─────────────────┐
                    │   Event Bus      │
                    └──┬──────┬───────┘
                       │      │
              ┌────────┘      └────────┐
              ▼                        ▼
         LootHistory              Toast (UI)
         (SavedVars)              (notifications)
              │
              ▼
         UI (history panel)
```

## File Structure

| File | Purpose |
|---|---|
| [Core.lua](Core.lua) | Framework: event bus, WoW event registration API, SavedVariables, utilities, slash commands, test harness |
| [modules/LootDetector.lua](modules/LootDetector.lua) | Parses `CHAT_MSG_LOOT`, `QUEST_LOOT_RECEIVED`, `CHAT_MSG_SYSTEM` (pushed items), `CHAT_MSG_MONEY`; fires `ITEM_LOOTED` and `GOLD_LOOTED` |
| [modules/RollTracker.lua](modules/RollTracker.lua) | Tracks `START_LOOT_ROLL`, parses roll system messages, fires `ROLL_STARTED`/`ROLL_UPDATE`/`ROLL_ENDED` |
| [modules/LootHistory.lua](modules/LootHistory.lua) | Stores loot entries in SavedVariables, enforces size limits, fires `HISTORY_UPDATED` |
| [modules/RCLCIntegration.lua](modules/RCLCIntegration.lua) | Hooks RCLootCouncil: `OnLootTableReceived` → ROLL_STARTED, `OnAwardedReceived` → ROLL_ENDED |
| [modules/LRIntegration.lua](modules/LRIntegration.lua) | Hooks LootReserve: `RequestRoll` handler → ROLL_STARTED, `SendWinner` handler → ROLL_ENDED; tracks reserves via `RegisterListener` |
| [modules/Toast.lua](modules/Toast.lua) | Creates/animates toast pop-ups, manages stacking (up or down), shows roll/council/reserve progress |
| [modules/UI.lua](modules/UI.lua) | Movable anchor bar (hides on lock, reveals on hover) + standalone history pop-out with name/quality filters and session gold display |
| [modules/Config.lua](modules/Config.lua) | Settings panel (standalone + InterfaceOptions), quality dropdowns, sliders, checkboxes |
| [modules/Minimap.lua](modules/Minimap.lua) | Minimap "?" button, draggable around edge, left-click toggle / shift-click history / right-click config |

## Custom Events (Event Bus)

| Event | Payload | Fired by |
|---|---|---|
| `ITEM_LOOTED` | `{ itemLink, itemID, quality, count, player, isSelf, isGroupLoot, timestamp, icon }` | LootDetector |
| `GOLD_LOOTED` | `sessionCopper` (number) | LootDetector |
| `ROLL_STARTED` | `rollData` table | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_UPDATE` | `rollID, { player, rollType, number }` | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_ENDED` | `rollData` table (with `winner`, `rolls`, `finished`, `source` fields) | RollTracker, RCLCIntegration, LRIntegration |
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
- Gets addon reference via `LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")`
- Hooks `RC:OnLootTableReceived()` (fires on all clients) → `ROLL_STARTED` per session item
- Hooks `VF:OnAwardedReceived()` on the voting frame module → `ROLL_ENDED` with winner
- Registers `RCMLAwardSuccess` message (ML client bonus) and `RCSessionEnd` (cleanup)
- Uses rollID range 100000+ to avoid collisions with native rolls

### LootReserve (`modules/LRIntegration.lua`)
- Detects `LootReserve` via `IsAddOnLoaded`
- Registers reserve listener via `LootReserve:RegisterListener("RESERVES", "ItemTracker", callback)`
- Wraps `LootReserve.Comm.Handlers[12]` (RequestRoll opcode) → `ROLL_STARTED` with reserve info
- Wraps `LootReserve.Comm.Handlers[19]` (SendWinner opcode) → `ROLL_ENDED` with winner
- Uses rollID range 200000+ to avoid collisions

Both integrations are safe — they do nothing if the external addon is not installed, and all hooks are wrapped in `pcall`.

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

## Coding Conventions

- Module pattern: `local ModName = {}; IT.ModuleName = ModName`
- Debug logging: `IT:Debug("message")`
- Settings access: `IT.db.settings.<key>` (persisted SavedVariables)
- WoW event registration: `IT:RegisterEvent("EVENT_NAME", callback)` in module `Initialize()`
- Custom events via bus: `IT.Events:Subscribe("EVENT", callback)` / `IT.Events:Fire("EVENT", ...)`
- Module initialization wrapped in `pcall` — one failing module doesn't break others
- Locale-safe message parsing via `IT:FormatToPattern(globalString)` helper
- UI controls use `AddThinBorder()` helper and custom-drawn tracks (no BackdropTemplate on sliders)

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
