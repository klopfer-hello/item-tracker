--[[
    ItemTracker - GearGoalsAtlasLoot Module
    Single Responsibility: Provide source-data lookup (boss + raid) for goal
    items via AtlasLootClassic. No-op when AtlasLoot is not installed.

    Public API:
        GG.AtlasLoot:IsLoaded()                   -> boolean
        GG.AtlasLoot:GetSource(itemID)            -> { boss, raid } | nil
        GG.AtlasLoot:GetBiSItems(class, spec,     -> { itemID, ... } | nil
                                  phase, slotKey)

    The source lookup builds a reverse index on first call (itemID -> source).
    Index build is best-effort: if the AtlasLoot table layout differs from
    what we expect, the call returns nil and the addon falls back to manual
    entry. All AtlasLoot reads are pcall-guarded.
]]

local _, IT = ...

local AL = {}
-- Registered both top-level (so Core's InitializeModules picks it up) and
-- as a convenience alias under GearGoals for ergonomic access.
IT.GearGoalsAtlasLoot = AL
IT.GearGoals = IT.GearGoals or {}
IT.GearGoals.AtlasLoot = AL

local sourceIndex = nil   -- itemID -> { boss = "...", raid = "..." }
local indexBuilt  = false

-- ============================================================================
-- Detection
-- ============================================================================

function AL:IsLoaded()
    return _G.AtlasLoot ~= nil and _G.AtlasLoot.ItemDB ~= nil
end

-- ============================================================================
-- Reverse index build (lazy)
-- AtlasLoot organises its data as nested tables under
-- AtlasLoot.ItemDB.Storage[<addon>].<contentName>[<difficulty>] = {
--     { index, itemID, ... }, { index, itemID, ... }, ...
-- }
-- We walk the tree once and produce a flat itemID -> { boss, raid } map.
-- ============================================================================

-- Storage keys we should skip when iterating an addon's content. Addons
-- store both content nodes (instance tables) and helper functions / shared
-- data on the same table; we want only instance nodes.
local SKIP_STORAGE_KEYS = {
    ["__atlaslootdata"] = true,
}

local function safeName(node)
    if not node then return nil end
    if type(node.name) == "string" and node.name ~= "" then return node.name end
    return nil
end

--- Walk a boss-level table, harvesting itemIDs from every numeric-keyed
--- difficulty bucket. Each bucket is an array of `{rank, payload, ...}` rows
--- where the payload is an itemID (number) for real items or a string for
--- header rows; we only keep the numeric payloads.
local function walkBoss(bossName, raidName, bossNode)
    if type(bossNode) ~= "table" then return end
    for k, v in pairs(bossNode) do
        if type(k) == "number" and type(v) == "table" then
            for _, entry in ipairs(v) do
                if type(entry) == "table" and type(entry[2]) == "number" then
                    local itemID = entry[2]
                    if itemID and not sourceIndex[itemID] then
                        sourceIndex[itemID] = { boss = bossName, raid = raidName }
                    end
                end
            end
        end
    end
end

--- Walk an instance content node. AtlasLoot stores the boss list under
--- `instanceNode.items` (numeric-indexed array); each element is a boss
--- with its own `.name` and difficulty buckets. Some content nodes (like
--- KEYS tables in dungeons-and-raids) also place difficulty buckets
--- directly on the instance node, so we walk both shapes.
local function walkInstance(raidName, instanceNode)
    if type(instanceNode) ~= "table" then return end

    if type(instanceNode.items) == "table" then
        for _, boss in ipairs(instanceNode.items) do
            if type(boss) == "table" then
                local bossName = safeName(boss) or raidName
                walkBoss(bossName, raidName, boss)
            end
        end
    end

    -- Fallback: difficulty buckets sometimes live directly on the node
    -- (typical of KEYS / loose-items entries with no nested boss list).
    walkBoss(raidName, raidName, instanceNode)
end

-- Sibling AtlasLoot plugins that contribute *boss / vendor / faction / PvP*
-- source data. Most are LoadOnDemand and dormant; we force-load them so
-- their data shows up in `Storage` for the walker.
--
-- NOTE: Crafting is deliberately excluded. Its tables group items by recipe
-- category (e.g. Alchemy → Elixirs) which produces nonsense "boss · raid"
-- strings like "Elixirs · Alchemy" for any item that happens to be
-- referenced from those tables. Collections IS included because it owns
-- the legitimate vendor sections like "'Badge of Justice' Vendor".
local SIBLING_PLUGINS = {
    "AtlasLootClassic_Factions",
    "AtlasLootClassic_PvP",
    "AtlasLootClassic_Collections",
}

local siblingsLoaded = false

local function ensureSiblingsLoaded()
    if siblingsLoaded then return end
    siblingsLoaded = true
    if not LoadAddOn then return end
    for _, name in ipairs(SIBLING_PLUGINS) do
        if not (IsAddOnLoaded and IsAddOnLoaded(name)) then
            pcall(LoadAddOn, name)
        end
    end
end

-- Walk addons in this order so a deterministic "first wins" assigns the
-- best-quality source. DungeonsAndRaids is highest-quality (real boss
-- drops); vendor / rep / PvP entries fill in items not in raids.
local PLUGIN_PRIORITY = {
    "AtlasLootClassic_DungeonsAndRaids",
    "AtlasLootClassic_Factions",
    "AtlasLootClassic_PvP",
    "AtlasLootClassic_Collections",
}

local function buildIndex()
    indexBuilt = true
    sourceIndex = {}
    if not AL:IsLoaded() then return end

    ensureSiblingsLoaded()

    local ok, db = pcall(function() return _G.AtlasLoot.ItemDB.Storage end)
    if not ok or not db then return end

    local function walkAddon(addonData)
        if type(addonData) ~= "table" then return end
        for contentKey, contentNode in pairs(addonData) do
            if type(contentNode) == "table"
               and type(contentKey) == "string"
               and not SKIP_STORAGE_KEYS[contentKey] then
                local raidName = safeName(contentNode) or contentKey
                pcall(walkInstance, raidName, contentNode)
            end
        end
    end

    -- Priority pass first.
    local visited = {}
    for _, addonKey in ipairs(PLUGIN_PRIORITY) do
        if db[addonKey] then
            walkAddon(db[addonKey])
            visited[addonKey] = true
        end
    end
    -- Catch any other registered addons we don't know about.
    for addonKey, addonData in pairs(db) do
        if not visited[addonKey] then walkAddon(addonData) end
    end
end

-- ============================================================================
-- Public lookups
-- ============================================================================

function AL:GetSource(itemID)
    if not itemID then return nil end
    if not indexBuilt then buildIndex() end
    return sourceIndex and sourceIndex[itemID]
end

--- Force a (re)build of the reverse index now and return the resulting size.
--- Used by `/it gear atlasloot-stats` to bypass the lazy gate.
function AL:BuildIndexNow()
    indexBuilt = false
    buildIndex()
    if not sourceIndex then return 0 end
    local n = 0
    for _ in pairs(sourceIndex) do n = n + 1 end
    return n
end

--- Diagnostic snapshot of the index — for debugging the boss/raid walker.
--- Returns: { hasAtlasLoot, drInLoaded, indexSize, samples = {{itemID, boss, raid}, ...} }
function AL:GetReverseIndexStats(sampleSize)
    sampleSize = sampleSize or 5
    local stats = {
        hasAtlasLoot = self:IsLoaded(),
        drLoaded     = (IsAddOnLoaded and IsAddOnLoaded("AtlasLootClassic_DungeonsAndRaids")) or false,
        storageKeys  = {},
        indexSize    = 0,
        samples      = {},
    }
    if _G.AtlasLoot and _G.AtlasLoot.ItemDB and _G.AtlasLoot.ItemDB.Storage then
        for k in pairs(_G.AtlasLoot.ItemDB.Storage) do
            table.insert(stats.storageKeys, tostring(k))
        end
    end
    stats.indexSize = self:BuildIndexNow()
    if sourceIndex then
        local taken = 0
        for itemID, src in pairs(sourceIndex) do
            if taken >= sampleSize then break end
            table.insert(stats.samples, {
                itemID = itemID,
                boss   = src.boss,
                raid   = src.raid,
            })
            taken = taken + 1
        end
    end
    return stats
end

local function formatSourceLabel(src)
    if not src then return nil end
    if src.boss and src.raid and src.boss ~= src.raid then
        return src.boss .. " · " .. src.raid
    end
    return src.boss or src.raid
end

-- ============================================================================
-- Tier-set redemption fallback
--
-- AtlasLoot's `DungeonsAndRaids` data describes T4/T5/T6 sets via *set IDs*
-- (e.g. setID 645 = Warlock T4 Voidheart) — not the individual itemIDs in
-- those sets — so the reverse-index walker can't label tier-set pieces
-- directly. WoW's `GetItemInfo(itemID)` returns the `setID` (16th return,
-- and nil for non-set items), which we cross-reference against the static
-- list of T4/T5/T6 set IDs lifted from
-- AtlasLootClassic_DungeonsAndRaids/data-tbc.lua (lines 79-158).
-- ============================================================================

local TIER_SET_IDS = {
    T4 = { 645, 663, 664, 621, 651, 654, 655, 648, 638, 639, 640, 631, 632, 633, 624, 625, 626 },
    T5 = { 646, 665, 666, 622, 652, 656, 657, 649, 642, 643, 641, 634, 635, 636, 627, 628, 629 },
    T6 = { 670, 675, 674, 668, 669, 673, 672, 671, 678, 677, 676, 683, 684, 682, 681, 679, 680 },
}

local TIER_LABEL = {
    T4 = "Tier 4 token vendor (Kara . Gruul . Mag)",
    T5 = "Tier 5 token vendor (SSC . Tempest Keep)",
    T6 = "Tier 6 token vendor (Hyjal . Black Temple)",
}

-- Build setID -> tier reverse map at file load.
local SET_TO_TIER = {}
for tier, ids in pairs(TIER_SET_IDS) do
    for _, sid in ipairs(ids) do
        SET_TO_TIER[sid] = tier
    end
end

local function tierLabelFor(itemID)
    if not itemID then return nil end
    -- 16th return of GetItemInfo is setID (or nil for non-set items).
    -- Items not yet in the WoW client cache return nothing; the tooltip /
    -- chat / loot hooks in the autocomplete cache pre-warm most of these.
    local setID = select(16, GetItemInfo(itemID))
    if type(setID) ~= "number" or setID <= 0 then return nil end
    local tier = SET_TO_TIER[setID]
    return tier and TIER_LABEL[tier] or nil
end

--- Resolve a `boss · raid` (or single-name) label for an itemID.
--- Lookup priority:
---   1. Direct lookup in the AtlasLoot reverse index.
---   2. Hardcoded Tokens DB chain: if `IT.GearGoalsTokens` knows this item
---      is the explicit redemption of a class token, inherit the token's
---      source (e.g. Cyclone Helm via Helm of the Fallen Hero, when the
---      Tokens DB maps that itemID to that token).
---   3. Tier-set membership fallback: if WoW's set API recognises this
---      item as a member of a T4/T5/T6 set, return a generic tier label.
---      Covers every tier-set piece without per-item DB maintenance.
function AL:GetSourceLabel(itemID)
    local label = formatSourceLabel(self:GetSource(itemID))
    if label then return label end

    local Tokens = IT.GearGoalsTokens
    if Tokens and Tokens.GetTokenFor then
        local tokenID = Tokens:GetTokenFor(itemID)
        if tokenID then
            label = formatSourceLabel(self:GetSource(tokenID))
            if label then return label end
        end
    end

    return tierLabelFor(itemID)
end

-- ============================================================================
-- TBCA_BIS plugin reader
--
-- Plugin layout (from AtlasLootClassic_TBCA_BIS/data.lua + runtime.lua):
--   AtlasLoot.ItemDB.Storage["AtlasLootClassic_TBCA_BIS"][<specKey>] = {
--       name = "...",
--       items = {
--           [1] = { name = "Head", [P1_DIFF]={{rank,id},...}, [P2_DIFF]=..., },
--           [2] = { name = "Neck", ...                                       },
--           ...
--       },
--   }
-- specKey is a class+spec string from runtime.lua's SPEC_TO_CONTENT, e.g.
-- "ShamanRestoration", "DruidBalance", "WarriorFury".
-- The slot ordering in `items` follows runtime.lua's SLOT_KEYS: Head, Neck,
-- Shoulders, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Ring, Trinket,
-- Main Hand, Off Hand, One Hand, Two Hand, Ranged.
-- The plugin is LoadOnDemand — we force-load it via LoadAddOn on first read.
-- ============================================================================

local TBCA_ADDON = "AtlasLootClassic_TBCA_BIS"

-- Map our INVSLOT_* IDs to one or more AtlasLoot SLOT_KEYS strings. Some
-- weapon slots span multiple keys because the plugin lists 1H/2H/MH/OH
-- separately depending on spec.
local SLOT_TO_TBCA_KEYS = {
    [INVSLOT_HEAD]     = { "Head" },
    [INVSLOT_NECK]     = { "Neck" },
    [INVSLOT_SHOULDER] = { "Shoulders" },
    [INVSLOT_BACK]     = { "Back" },
    [INVSLOT_CHEST]    = { "Chest" },
    [INVSLOT_WRIST]    = { "Wrist" },
    [INVSLOT_HAND]     = { "Hands" },
    [INVSLOT_WAIST]    = { "Waist" },
    [INVSLOT_LEGS]     = { "Legs" },
    [INVSLOT_FEET]     = { "Feet" },
    [INVSLOT_FINGER1]  = { "Ring" },
    [INVSLOT_FINGER2]  = { "Ring" },
    [INVSLOT_TRINKET1] = { "Trinket" },
    [INVSLOT_TRINKET2] = { "Trinket" },
    [INVSLOT_MAINHAND] = { "Main Hand", "Two Hand", "One Hand" },
    [INVSLOT_OFFHAND]  = { "Off Hand", "One Hand" },
    [INVSLOT_RANGED]   = { "Ranged" },
}

-- Our phase ids -> TBCA_BIS difficulty index. The plugin defines P1..P5 via
-- AddDifficulty; AtlasLoot returns a small integer for the difficulty key,
-- which is what the per-slot tables index by. Phase 3.5 (ZA) maps to P4
-- and Phase 4 (Sunwell) to P5 — verify in-game; if mapping is wrong the
-- worst case is no autocomplete results for that phase.
local PHASE_TO_DIFF = {
    ["1"]   = 1,
    ["2"]   = 2,
    ["3"]   = 3,
    ["3.5"] = 4,
    ["4"]   = 5,
}

-- Cache the loaded state so we don't keep calling LoadAddOn.
local tbcaLoadAttempted = false
local tbcaLoadOK        = false

local function ensureTBCALoaded()
    if tbcaLoadAttempted then return tbcaLoadOK end
    tbcaLoadAttempted = true

    if IsAddOnLoaded and IsAddOnLoaded(TBCA_ADDON) then
        tbcaLoadOK = true
        return true
    end
    if not LoadAddOn then return false end
    local loaded = LoadAddOn(TBCA_ADDON)
    tbcaLoadOK = loaded and true or false
    return tbcaLoadOK
end

local function tbcaStorage()
    if not ensureTBCALoaded() then return nil end
    if not _G.AtlasLoot or not _G.AtlasLoot.ItemDB or not _G.AtlasLoot.ItemDB.Storage then
        return nil
    end
    return _G.AtlasLoot.ItemDB.Storage[TBCA_ADDON]
end

-- All TBCA spec keys for the player's class. We don't try to infer which spec
-- the user is "currently" gearing — the autocomplete unions everything for
-- the class and lets the search query narrow.
local function specsForPlayerClass()
    local _, class = UnitClass("player")
    if not class then return {} end
    local store = tbcaStorage()
    if not store then return {} end
    local out = {}
    -- Class is the all-caps WoW class token (e.g. "SHAMAN"); TBCA keys use
    -- mixed-case (e.g. "ShamanRestoration"). Compare case-insensitively
    -- against the prefix.
    local lower = class:lower()
    for k in pairs(store) do
        if type(k) == "string" and k:lower():sub(1, #lower) == lower then
            table.insert(out, k)
        end
    end
    return out
end

--- Return an array of itemIDs ranked-then-deduplicated for the given INV
--- slot at `phase`. Walks every TBCA spec for the player's class and unions
--- their picks. Returns nil if TBCA_BIS isn't available or the slot/phase
--- isn't represented.
function AL:GetBiSItemsForSlot(slotID, phase)
    local diff = PHASE_TO_DIFF[phase]
    if not diff then return nil end
    local tbcaSlotKeys = SLOT_TO_TBCA_KEYS[slotID]
    if not tbcaSlotKeys then return nil end
    local store = tbcaStorage()
    if not store then return nil end

    -- Collect (rank, itemID) tuples across every relevant spec + slot key,
    -- then sort by rank ascending and dedup.
    local tuples = {}

    local ok, err = pcall(function()
        for _, specKey in ipairs(specsForPlayerClass()) do
            local entry = store[specKey]
            if entry and type(entry.items) == "table" then
                for _, slotEntry in ipairs(entry.items) do
                    if type(slotEntry) == "table" and slotEntry.name then
                        local matches = false
                        for _, wantKey in ipairs(tbcaSlotKeys) do
                            if slotEntry.name == wantKey then matches = true; break end
                        end
                        if matches then
                            local diffBucket = slotEntry[diff]
                            if type(diffBucket) == "table" then
                                for _, pair in ipairs(diffBucket) do
                                    -- pair = { rank, itemID }
                                    if type(pair) == "table"
                                       and type(pair[1]) == "number"
                                       and type(pair[2]) == "number" then
                                        table.insert(tuples, { rank = pair[1], itemID = pair[2] })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    if not ok then
        IT:Debug("TBCA_BIS read error: " .. tostring(err))
        return nil
    end

    if #tuples == 0 then return nil end

    table.sort(tuples, function(a, b) return a.rank < b.rank end)

    local out, seenID = {}, {}
    for _, t in ipairs(tuples) do
        if not seenID[t.itemID] then
            seenID[t.itemID] = true
            table.insert(out, t.itemID)
        end
    end
    return out
end

--- Legacy stub kept for the brief 09 import flow (different shape: per-spec).
--- The autocomplete provider uses GetBiSItemsForSlot above.
function AL:GetBiSItems(class, spec, phase, slotKey)
    return nil
end

--- Diagnostic: report the TBCA_BIS load state for `/it gear atlasloot-stats`
--- when that command lands.
function AL:GetTBCAStatus()
    local loaded = (IsAddOnLoaded and IsAddOnLoaded(TBCA_ADDON)) or false
    local store  = tbcaStorage()
    local specs  = store and specsForPlayerClass() or {}
    return {
        loaded     = loaded or tbcaLoadOK,
        attempted  = tbcaLoadAttempted,
        hasStorage = store ~= nil,
        specCount  = #specs,
    }
end

function AL:Initialize()
    -- Nothing to do at load time; both the source index and the TBCA_BIS
    -- reader build / load lazily on first access.
end
