# Klopfer's Item Tracker - CLAUDE.md

## Project Overview

**Klopfer's Item Tracker** is a World of Warcraft addon for **TBC Classic Anniversary** (interface version 20506, game version 2.5.6). It bundles three big features behind a single addon:

1. **Loot tracking** — toast notifications for looted items, group/raid roll tracking, RCLootCouncil + LootReserve integration, scrollable loot history.
2. **Session gold** — running gold/hr rate with vendor and Auctionator AH valuation, optional LDB DataText.
3. **GearGoals** — character-scoped, spec-aware, phase-organised BiS / loadout tracker with drop-alert popups, AtlasLoot source labels, and tier-set token redemption.

The folder is still named `ItemTracker` (and the SavedVariables key is still `ItemTrackerDB`) for backwards compatibility — only the user-facing branding changed. The addon uses a global namespace `IT` (also `ItemTracker`) populated via the addon vararg `local ADDON_NAME, IT = ...`. Chat output is prefixed `[KIT]`. Slash commands: `/kit` (primary), `/it` and `/itemtracker` kept as aliases. The dispatcher itself is intentionally minimal — most interaction is through the UI; the CLI keeps only `status`, `clear`, `debug`, `version`, and the `test …` simulation harness.

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
    ├─ CHAT_MSG_LOOT ────────→ LootDetector ──→ ITEM_LOOTED
    ├─ QUEST_LOOT_RECEIVED ──→ LootDetector ──→ ITEM_LOOTED
    ├─ CHAT_MSG_SYSTEM ──────→ LootDetector ──→ ITEM_LOOTED (pushed items)
    ├─ CHAT_MSG_MONEY ───────→ LootDetector ──→ GOLD_LOOTED
    │
    ├─ START_LOOT_ROLL ──────────→ RollTracker ──→ ROLL_STARTED
    ├─ LOOT_HISTORY_ROLL_CHANGED → RollTracker ──→ ROLL_UPDATE
    ├─ LOOT_ROLLS_COMPLETE ──────→ RollTracker ──→ ROLL_ENDED
    │
    ├─ RC OnLootTableReceived → RCLCIntegration → ROLL_STARTED / ROLL_ENDED
    ├─ LR RequestRoll/Winner ─→ LRIntegration ──→ ROLL_STARTED / ROLL_ENDED
    │
    ├─ BANKFRAME_OPENED / PLAYERBANKSLOTS_CHANGED / BAG_UPDATE
    │       └────────────────→ GearGoals: rebuild charDB.bankItems
    │
    ▼
                    ┌──────────────────┐
                    │    Event Bus     │
                    └─┬─┬──────────┬───┘
                      │ │          │
              ┌───────┘ │          └────────────┐
              ▼         ▼                       ▼
         LootHistory  Toast (notifications)  GoldTracker ──→ ElvUIDataText
         (SavedVars)                         (vendor/AH/hr)  (LDB feed)
              │
              ▼
         ITEM_LOOTED ──→ GearGoalsDetector ──→ GEAR_GOAL_DROPPED
                                                    │
                                                    ▼
                                              GearGoalsAlert (drop popup)
                                              GearGoalsUI    (LOOT LOG tab)
```

## File Structure

| File | Purpose |
|---|---|
| [Core.lua](Core.lua) | Framework: event bus, WoW event registration API, SavedVariables, utilities, slash commands, test harness |
| [modules/Theme.lua](modules/Theme.lua) | Canonical dark/gold palette + `SetColor` / `AddBackground` / `AddBorder` helpers shared by every UI module |
| [modules/LootDetector.lua](modules/LootDetector.lua) | Parses `CHAT_MSG_LOOT`, `QUEST_LOOT_RECEIVED`, `CHAT_MSG_SYSTEM` (pushed items), `CHAT_MSG_MONEY`; fires `ITEM_LOOTED` and `GOLD_LOOTED` |
| [modules/RollTracker.lua](modules/RollTracker.lua) | Tracks rolls via `START_LOOT_ROLL`, `C_LootHistory` API, and `LOOT_ROLLS_COMPLETE`; fires `ROLL_STARTED`/`ROLL_UPDATE`/`ROLL_ENDED`; safety timeout via `GetLootRollTimeLeft` polling |
| [modules/LootHistory.lua](modules/LootHistory.lua) | Stores loot entries in SavedVariables, enforces size limits, migrates legacy session-time stamps to epoch on load, fires `HISTORY_UPDATED` |
| [modules/RCLCIntegration.lua](modules/RCLCIntegration.lua) | Hooks RCLootCouncil: `OnLootTableReceived` → ROLL_STARTED, `OnAwardedReceived` → ROLL_ENDED |
| [modules/LRIntegration.lua](modules/LRIntegration.lua) | Hooks LootReserve: `RequestRoll` handler → ROLL_STARTED, `SendWinner` handler → ROLL_ENDED; tracks reserves via `RegisterListener` |
| [modules/GoldTracker.lua](modules/GoldTracker.lua) | Session gold/hr tracking: vendor value (`GetItemInfo` sellPrice) and AH value (Auctionator API) for self-looted items; fires `GOLD_RATES_UPDATED` |
| [modules/ElvUIDataText.lua](modules/ElvUIDataText.lua) | LDB (LibDataBroker) data source: gold/hr text, tooltip with vendor/AH breakdown, click handlers (left → Gear Tracker, shift → LOOT LOG, right → reset session); safe if LDB not available |
| [modules/Toast.lua](modules/Toast.lua) | Toast pop-ups for loot / rolls / gold; manages stacking up or down, recycles via a pool, draws roll panel for active rolls; uses `Theme.P` for colours, no `BackdropTemplate` |
| [modules/UI.lua](modules/UI.lua) | Movable anchor bar (the toast positioning frame). Click routes to `IT.GearGoalsUI:OpenLootLog`. The legacy history pop-out has been retired |
| [modules/Config.lua](modules/Config.lua) | Registers the parent Settings category (Esc → Interface → AddOns → Klopfer's Item Tracker) using the modern `Settings.RegisterAddOnSetting` + `CreateCheckbox` / `CreateSlider` / `CreateDropdown` flow (Molinari-style native widgets) |
| [modules/Minimap.lua](modules/Minimap.lua) | Minimap button: left-click toggles the Gear Tracker, shift-click jumps to the LOOT LOG tab |
| [modules/GearGoals.lua](modules/GearGoals.lua) | GearGoals storage + state. Spec auto-detect, equipped scan, rank-suppression, phase + loadout management, in-memory dedup, persistent bank-content cache (`charDB.bankItems`), `EncodePhase` / `DecodePhase` wire format |
| [modules/GearGoalsTokens.lua](modules/GearGoalsTokens.lua) | Tier-set token definitions and lookup; auto-derives token-to-piece mappings from `setID` + `equipLoc` + class |
| [modules/GearGoalsAtlasLoot.lua](modules/GearGoalsAtlasLoot.lua) | AtlasLootClassic reader. Reverse index from itemID to `boss · raid` source label, plus `GetTBCASpecsForClass` / `GetBiSItemsForSpec` for bulk-importing curated BiS lists |
| [modules/GearGoalsDetector.lua](modules/GearGoalsDetector.lua) | Subscribes to `ITEM_LOOTED` + chat-link scanner over party/raid/whisper; fires `GEAR_GOAL_DROPPED` when a drop matches a goal; honours phase + rank suppression |
| [modules/GearGoalsTooltip.lua](modules/GearGoalsTooltip.lua) | `GameTooltip:HookScript("OnTooltipSetItem")` integration; appends "On your ⟨spec⟩ list (⟨phase⟩, rank ⟨n⟩)" lines |
| [modules/GearGoalsAlert.lua](modules/GearGoalsAlert.lua) | Drop popup (movable, fade-in, pulsing corner brackets). MS / OS roll buttons, dismiss; ESC + Enter handling |
| [modules/GearGoalsUI.lua](modules/GearGoalsUI.lua) | Main window. Tabs: LOADOUT (slot grid + filter), RAIDS (raid pivot), LOOT LOG (history with ALL / WISHLIST scope + name + quality filters). Inline add / edit / import dialog, sidebar with phase-summary status breakdown |
| [modules/GearGoalsConfig.lua](modules/GearGoalsConfig.lua) | GearGoals sub-category in the Settings panel (canvas layout, native templates). Phase row buttons (TBCA_BIS pattern), notify-sound + popup-animations checkboxes, Open / Reset-popup-position buttons |
| [modules/GearGoalsCharButton.lua](modules/GearGoalsCharButton.lua) | "K" badge anchored to PaperDollFrame so the Gear Tracker is one click away from the Character pane |

## Custom Events (Event Bus)

| Event | Payload | Fired by |
|---|---|---|
| `ITEM_LOOTED` | `{ itemLink, itemID, quality, count, player, isSelf, isGroupLoot, timestamp, icon }` | LootDetector |
| `ITEM_VALUE` | same shape as `ITEM_LOOTED`, fires for all self-looted items regardless of quality threshold | LootDetector |
| `GOLD_LOOTED` | `sessionCopper` (number) | LootDetector |
| `ROLL_STARTED` | `rollData` table | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_UPDATE` | `rollID, { player, rollType, number }` | RollTracker, RCLCIntegration, LRIntegration |
| `ROLL_ENDED` | `rollData` table (with `winner`, `rolls`, `finished`, `source` fields) | RollTracker, RCLCIntegration, LRIntegration |
| `GOLD_RATES_UPDATED` | (none) | GoldTracker |
| `HISTORY_UPDATED` | (none) | LootHistory |
| `GEAR_GOAL_DROPPED` | `{ itemID, itemLink, slotID, looter, fromChat, matches }` (matches = list of `{ specKey, phase, slotID, rank, isMainSpec, isToken, goalItemID }`) | GearGoalsDetector |
| `GEAR_GOAL_LIST_CHANGED` | optional `{ loadoutID, phase, reason }` | GearGoals |
| `GEAR_GOALS_PHASE_CHANGED` | `{ phase }` | GearGoals |
| `GEAR_GOALS_LOADOUT_CHANGED` | (none — UI-side reactive event) | GearGoalsUI |
| `PLAYER_READY` | (none) | Core |
| `PLAYER_LOGOUT` | (none) | Core |

## SavedVariables Schema

### `ItemTrackerDB` (account-wide)

```lua
{
    settings = {
        enabled               = true,
        soloQualityThreshold  = 2,    -- 0=Poor .. 5=Legendary
        groupQualityThreshold = 2,
        toastDuration         = 8,    -- seconds
        toastMaxVisible       = 5,
        toastUpward           = true,
        toastGold             = false,
        historySize           = 100,
        locked                = false,
        position              = nil,   -- anchor bar { point, relativePoint, x, y }
        minimapAngle          = 225,
        showMinimap           = true,
        chatOutput            = true,
        gearGoals = {
            -- currentPhase moved to ItemTrackerCharDB (per-character) so alts
            -- can chase different phases independently. Migrated on first
            -- login of each character; the old account-wide key may still
            -- exist on upgraded accounts but is no longer read.
            notifySound      = true,
            popupAnimations  = true,    -- fade-in + corner pulse on the BiS popup
            popupAnchor      = nil,     -- { point, relativePoint, x, y }
            seenItems        = {},      -- [itemID] = { name, quality, lastSeen }
        },
    },
    history = {
        -- ordered newest-first; each entry:
        -- { itemLink, itemID, quality, count, icon, player, isSelf,
        --   isGroupLoot, timestamp, wasRolled, rolls, winner }
    },
    lootHistoryTimestampsMigrated = true,  -- one-shot migration flag
}
```

### `ItemTrackerCharDB` (per-character)

```lua
{
    -- Active phase for goal status, popup eligibility, and the sidebar
    -- "CURRENT PHASE" indicator. Per-character so each alt can be parked
    -- in a different phase. Seeded from the old account-wide value on first
    -- login after upgrade; defaults to "pre-raid" on a fresh character.
    currentPhase   = "pre-raid",

    -- Loadouts (pseudo-spec containers — main / off / pvp / etc.).
    loadouts       = { { id = "...", name = "Main", color = "#FFCC33" }, ... },
    loadoutCounter = 0,

    -- Goals: nested by loadoutID → phase → slotID → list of picks.
    goals = {
        [loadoutID] = {
            [phase] = {                       -- "pre-raid" / "1" / "2" / "3" / "3.5" / "4"
                [slotID] = {
                    { itemID = 30183, rank = 1, obtained = false, note = "..." },
                    { itemID = 28744, rank = 2, obtained = false },
                },
            },
        },
    },

    -- Persistent snapshot of bank contents — { [itemID] = true }.
    -- Refreshed whenever the bank UI is visible; survives logout, /reload,
    -- and travel away from the banker so OWNED status sticks.
    bankItems = {},
}
```

## External Addon Integration

### RCLootCouncil (`modules/RCLCIntegration.lua`)
- Detects `RCLootCouncil_Classic` or `RCLootCouncil` via `IsAddOnLoaded`
- Gets addon reference via `LibStub("AceAddon-3.0"):GetAddon()` — tries `"RCLootCouncil_Classic"` first, then `"RCLootCouncil"`
- Hooks `RC:OnLootTableReceived()` → `ROLL_STARTED` per session item; guarded by `rc.enabled` and `entry.link` checks to skip RCLC's internal retry/reschedule calls
- Hooks `VF:OnResponseReceived()` → `ROLL_UPDATE` with RCLC colored response text (council members only)
- Hooks `VF:OnAwardedReceived()` → `ROLL_ENDED` with winner (council members only)
- Subscribes to `ITEM_LOOTED` as a fallback award detection path for non-council players, plus a 2-second polling timer that checks RCLC's `GetLootTable()` for the `awarded` field
- 3-minute safety timeout auto-finishes any session that wasn't resolved by other detection paths
- Uses rollID range 100000+ to avoid collisions with native rolls

### LootReserve (`modules/LRIntegration.lua`)
- Detects `LootReserve` via `IsAddOnLoaded`
- Registers reserve listener via `LootReserve:RegisterListener("RESERVES", "ItemTracker", callback)` (the `"ItemTracker"` tag is an internal identifier and stays for back-compat with persisted state — see CLAUDE.md note in commit `e46eddd`)
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
- Updates text via `GOLD_RATES_UPDATED` event subscription

### AtlasLootClassic (`modules/GearGoalsAtlasLoot.lua`)
- Loads `AtlasLootClassic_DungeonsAndRaids` (and optionally `_TBCA_BIS`, `_Factions`, `_Collections`) via `LoadAddOn` to populate the Storage tables
- Builds a reverse index from itemID → `{ boss, raid }` for source labels in the LOADOUT pane
- `GetTBCASpecsForClass()` returns the canonical TBCA_BIS spec keys for the player's class; `GetBiSItemsForSpec(spec, phase, slotID, topN)` returns the curated picks for bulk import
- All reads guarded by `pcall`; the whole module no-ops cleanly when AtlasLoot is missing

All integrations are safe — they do nothing if the external addon is not installed, and all hooks are wrapped in `pcall`.

## Game Version Notes (Critical)

- **TBC Classic Anniversary uses the `C_Container` namespace**. A compatibility shim in [Core.lua](Core.lua) maps legacy globals (`GetContainerNumSlots`, `GetContainerItemLink`, etc.) to `C_Container` equivalents. `C_Container.GetContainerItemInfo` returns a **table**; the shim wraps it back to legacy multi-return form.
- **Modern Settings API**: `Settings.RegisterCanvasLayoutCategory` / `RegisterAddOnCategory` / `RegisterAddOnSetting` is what the in-game Settings panel actually consumes in 2.5.5. The legacy `InterfaceOptions_AddCategory` exists as a stub but registrations made through it are silently dropped — see commit `e46efa9` for the migration. Use `Settings.OpenToCategory(category:GetID())` to jump to a panel.
- **Bank slots only return data while the bank UI is open** (or has been opened in the current session). For ownership detection while away from the banker, GearGoals snapshots bank contents into `charDB.bankItems` whenever the bank is visible.
- **Lua 5.1**: use **decimal** string escapes (`\226\128\148` for em-dash), never `\xNN` hex. WoW's default font doesn't cover the Geometric Shapes (▲▼) or Arrows (↑↓ ↵) blocks; prefer ASCII or boxed-key text like `[Enter]`.
- **`UNIT_SPELLCAST_*` event signature**: 3-arg `(unit, castGUID, spellID)` in 2.5.5.
- **`QUEST_LOOT_RECEIVED(questID, itemLink, count)`** fires when quest reward items are received from NPCs; `LOOT_ITEM_PUSHED_SELF` is the global string used as a fallback.
- **`C_LootHistory`** is available — `GetItem()`, `GetPlayerInfo()`, `GetNumItems()`. `LOOT_HISTORY_ROLL_CHANGED` and `LOOT_ROLLS_COMPLETE` events fire correctly.
- **`GetLootRollTimeLeft(rollID)`** is available; wrapped in `pcall` for safety.

## Coding Conventions

- Module pattern: `local _, IT = ...; local Mod = {}; IT.ModuleName = Mod`.
- Debug logging: `IT:Debug("message")` (silent unless `/kit debug` is on).
- Settings access: `IT.db.settings.<key>` (account-wide) or `IT.db.settings.gearGoals.<key>` for the GearGoals scope; per-character → `IT.charDB.<key>`.
- Apply defaults via the file's local `DeepDefaults` helper at the top of `Initialize`, before reading any settings.
- WoW event registration: `IT:RegisterEvent("EVENT_NAME", callback)` from `Mod:Initialize()`.
- Custom events via bus: `IT.Events:Subscribe("EVENT", callback)` / `IT.Events:Fire("EVENT", ...)`. After data mutations, fire the appropriate event and let the UI refresh via its existing subscriptions — don't call `UI:Refresh` from non-UI modules.
- Module initialization wrapped in `pcall` — one failing module doesn't break others.
- Locale-safe message parsing via `IT:FormatToPattern(globalString)` helper.
- **Frame styling**: shared dark/gold palette and helpers come from `IT.Theme` (`P`, `SetColor`, `AddBackground`, `AddBorder`). No `BackdropTemplate` in new code — manual borders only.
- **Buttons**: `CreateFrame("Button", ...)`. `Frame` does not support `RegisterForClicks` / `OnClick` in TBC 2.5.5.
- **Forward-declare** any file-local helper that's referenced before its definition site.

## Reference Addons

Two locally installed addons used as references:

- **`FishingKit`** (`d:\Games\World of Warcraft\_anniversary_\Interface\AddOns\FishingKit`) — TBC Classic API patterns, the slider helper.
- **`Molinari`** (`d:\Games\World of Warcraft\_anniversary_\Interface\AddOns\Molinari`) — modern `Settings.*` registration pattern; consult `libs/Dashi/modules/settings.lua` when extending the parent settings panel.
- **`TBCA_BIS`** (`d:\Games\World of Warcraft\_anniversary_\Interface\AddOns\TBCA_BIS`) — phase-row button pattern (numbered buttons + `LockHighlight` on selection) used in `GearGoalsConfig`.

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
