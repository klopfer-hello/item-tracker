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

local function safeName(node)
    if not node then return nil end
    if type(node.name) == "string" then return node.name end
    return nil
end

local function walkBoss(bossName, raidName, bossNode)
    if type(bossNode) ~= "table" then return end
    for k, v in pairs(bossNode) do
        if type(v) == "table" and type(k) ~= "string" then
            -- Difficulty buckets (numeric keys); each holds the loot list
            for _, entry in ipairs(v) do
                if type(entry) == "table" and type(entry[2]) == "number" then
                    local itemID = entry[2]
                    -- First wins; don't overwrite (keeps highest-tier source)
                    if itemID and not sourceIndex[itemID] then
                        sourceIndex[itemID] = { boss = bossName, raid = raidName }
                    end
                end
            end
        end
    end
end

local function buildIndex()
    indexBuilt = true
    sourceIndex = {}
    if not AL:IsLoaded() then return end

    local ok, db = pcall(function() return _G.AtlasLoot.ItemDB.Storage end)
    if not ok or not db then return end

    for addonKey, addonData in pairs(db) do
        if type(addonData) == "table" then
            for contentName, contentNode in pairs(addonData) do
                if type(contentNode) == "table" and type(contentName) == "string" then
                    -- contentNode often has nested boss tables; walk one level
                    local raidName = safeName(contentNode) or contentName
                    for _, child in pairs(contentNode) do
                        if type(child) == "table" then
                            local bossName = safeName(child)
                            if bossName then
                                pcall(walkBoss, bossName, raidName, child)
                            end
                        end
                    end
                    -- Also try direct loot at this level
                    pcall(walkBoss, raidName, raidName, contentNode)
                end
            end
        end
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

function AL:GetSourceLabel(itemID)
    local src = self:GetSource(itemID)
    if not src then return nil end
    if src.boss and src.raid and src.boss ~= src.raid then
        return src.boss .. " · " .. src.raid
    end
    return src.boss or src.raid
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
