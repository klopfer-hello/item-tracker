--[[
    ItemTracker - LootHistory Module
    Single Responsibility: Persist loot entries in SavedVariables,
    enforce history size limits, and provide query access.

    Listens to:
        ITEM_LOOTED  — add entry to history
        ROLL_ENDED   — annotate existing entry with roll result, or add if new

    Fires:
        HISTORY_UPDATED — whenever the history list changes
]]

local _, IT = ...
local History = {}
IT.LootHistory = History

-- ============================================================================
-- Internal Data
-- ============================================================================

local history  -- reference to IT.db.history (set during Initialize)

-- ============================================================================
-- History Entry Structure
-- ============================================================================

--[[
    entry = {
        itemLink    = string,
        itemID      = number,
        quality     = number,
        count       = number,
        icon        = texture,
        player      = string,       -- who received the item
        isSelf      = boolean,
        isGroupLoot = boolean,
        timestamp   = number,       -- GetTime()
        wasRolled   = boolean,
        rolls       = { { player, rollType, number }, ... } | nil,
        winner      = string | nil,
    }
]]

-- ============================================================================
-- Core Operations
-- ============================================================================

function History:Add(entry)
    table.insert(history, 1, entry)  -- newest first
    self:EnforceLimit()
    IT.Events:Fire("HISTORY_UPDATED")
end

function History:EnforceLimit()
    local maxSize = IT.db.settings.historySize or 100
    while #history > maxSize do
        table.remove(history)
    end
end

function History:Clear()
    wipe(history)
    IT.Events:Fire("HISTORY_UPDATED")
end

function History:GetAll()
    return history
end

function History:GetCount()
    return #history
end

function History:GetEntry(index)
    return history[index]
end

-- ============================================================================
-- Find an existing entry by itemID + player within a time window.
-- Used to annotate loot entries with roll results.
-- ============================================================================

local MATCH_WINDOW = 30  -- seconds

function History:FindRecentByItem(itemID, maxAge)
    maxAge = maxAge or MATCH_WINDOW
    local now = GetTime()
    for i, entry in ipairs(history) do
        if entry.itemID == itemID and (now - entry.timestamp) < maxAge then
            return i, entry
        end
    end
    return nil, nil
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

local function OnItemLooted(lootEntry)
    -- Don't double-add items that are going through the roll system.
    -- RollTracker will handle those via ROLL_ENDED.
    if lootEntry.isGroupLoot then
        -- Check if there's an active roll for this item
        local activeRolls = IT.RollTracker and IT.RollTracker:GetActiveRolls()
        if activeRolls then
            for _, rollData in pairs(activeRolls) do
                if rollData.itemID == lootEntry.itemID and not rollData.finished then
                    return  -- skip; ROLL_ENDED will handle it
                end
            end
        end
    end

    History:Add({
        itemLink    = lootEntry.itemLink,
        itemID      = lootEntry.itemID,
        quality     = lootEntry.quality,
        count       = lootEntry.count,
        icon        = lootEntry.icon,
        player      = lootEntry.player,
        isSelf      = lootEntry.isSelf,
        isGroupLoot = lootEntry.isGroupLoot,
        timestamp   = lootEntry.timestamp,
        wasRolled   = false,
        rolls       = nil,
        winner      = nil,
    })
end

local function OnRollEnded(rollData)
    History:Add({
        itemLink    = rollData.itemLink,
        itemID      = rollData.itemID,
        quality     = rollData.quality,
        count       = rollData.count or 1,
        icon        = rollData.icon,
        player      = rollData.winner or "Nobody",
        isSelf      = (rollData.winner == UnitName("player")),
        isGroupLoot = true,
        timestamp   = rollData.startTime,
        wasRolled   = true,
        rolls       = rollData.rolls,
        winner      = rollData.winner,
    })
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function History:Initialize()
    history = IT.db.history
    IT.Events:Subscribe("ITEM_LOOTED", OnItemLooted)
    IT.Events:Subscribe("ROLL_ENDED", OnRollEnded)
end
