--[[
    ItemTracker - RollTracker Module
    Single Responsibility: Track group loot rolls (Need/Greed/Pass),
    maintain per-item roll state, and fire roll lifecycle events.

    Uses C_LootHistory API for reliable roll tracking — no chat parsing.

    Events fired:
        ROLL_STARTED  (rollData)         — a new roll began
        ROLL_UPDATE   (rollID, rollEntry) — someone rolled/passed
        ROLL_ENDED    (rollData)         — roll completed with a winner
]]

local _, IT = ...
local Tracker = {}
IT.RollTracker = Tracker

-- ============================================================================
-- State: active rolls keyed by rollID
-- ============================================================================

local activeRolls = {}  -- rollID → rollData

--[[
    rollData = {
        rollID      = number,
        itemLink    = string,
        itemID      = number,
        quality     = number,
        icon        = string|number,
        timeLeft    = number,       -- seconds
        startTime   = number,       -- GetTime()
        rolls       = {},           -- ordered list of { player, rollType, number }
        winner      = nil|string,
        finished    = false,
    }
]]

-- ============================================================================
-- C_LootHistory roll type mapping
-- ============================================================================

local ROLL_TYPE_MAP = {
    [0] = "pass",
    [1] = "need",
    [2] = "greed",
    [3] = "disenchant",
}

-- ============================================================================
-- Roll Start (WoW event)
-- ============================================================================

local function OnStartLootRoll(rollID, rollTime)
    if not IT.db.settings.enabled then return end

    local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant
        = GetLootRollItemInfo(rollID)
    local itemLink = GetLootRollItemLink(rollID)
    if not itemLink then return end

    local threshold = IT.db.settings.groupQualityThreshold
    if quality and quality < threshold then return end

    local rollData = {
        rollID    = rollID,
        itemLink  = itemLink,
        itemID    = IT:GetItemIDFromLink(itemLink),
        quality   = quality or 0,
        icon      = texture,
        count     = count or 1,
        timeLeft  = (rollTime or 60000) / 1000,
        startTime = GetTime(),
        rolls     = {},
        winner    = nil,
        finished  = false,
    }

    activeRolls[rollID] = rollData
    IT:Debug("Roll started: " .. itemLink .. " (rollID " .. rollID .. ")")
    IT.Events:Fire("ROLL_STARTED", rollData)
end

-- ============================================================================
-- Roll Updates via C_LootHistory
-- LOOT_HISTORY_ROLL_CHANGED fires when a player rolls/passes.
-- ============================================================================

local function OnLootHistoryRollChanged(historyIndex, playerIndex)
    local rollID = C_LootHistory.GetItem(historyIndex)
    if not rollID then return end

    local rollData = activeRolls[rollID]
    if not rollData or rollData.finished then return end

    local name, class, rollTypeID, roll, isWinner, isMe =
        C_LootHistory.GetPlayerInfo(historyIndex, playerIndex)
    if not name then return end

    local rollType = ROLL_TYPE_MAP[rollTypeID] or "pass"
    local entry = { player = name, rollType = rollType, number = roll or 0 }

    -- Update existing entry if player already recorded (event can re-fire)
    for _, existing in ipairs(rollData.rolls) do
        if existing.player == name then
            existing.rollType = rollType
            existing.number = roll or 0
            IT.Events:Fire("ROLL_UPDATE", rollID, entry)
            return
        end
    end

    table.insert(rollData.rolls, entry)
    IT:Debug("Roll update: " .. name .. " " .. rollType .. " " .. (roll or 0))
    IT.Events:Fire("ROLL_UPDATE", rollID, entry)
end

-- ============================================================================
-- Roll Completion via C_LootHistory
-- LOOT_ROLLS_COMPLETE / LOOT_HISTORY_ROLL_COMPLETE fire when a roll resolves.
-- Iterate history to find which tracked roll finished and who won.
-- ============================================================================

local function OnLootRollsComplete()
    local hid = 1
    while true do
        local rollID, itemLink, numPlayers, isDone = C_LootHistory.GetItem(hid)
        if not rollID then break end

        if isDone and activeRolls[rollID] and not activeRolls[rollID].finished then
            local winner = nil
            for j = 1, numPlayers do
                local name, class, rollTypeID, roll, isWinner, isMe =
                    C_LootHistory.GetPlayerInfo(hid, j)
                if isWinner then
                    winner = name
                    break
                end
            end
            Tracker:FinishRoll(rollID, winner)
        end

        hid = hid + 1
    end
end

-- ============================================================================
-- Roll Lifecycle
-- ============================================================================

function Tracker:FinishRoll(rollID, winner)
    local rollData = activeRolls[rollID]
    if not rollData or rollData.finished then return end

    rollData.finished = true
    rollData.winner = winner

    IT:Debug("Roll ended: " .. rollData.itemLink .. " → " .. (winner or "no winner"))
    IT.Events:Fire("ROLL_ENDED", rollData)

    -- Clean up after a short delay to allow UI to read final state
    C_Timer.After(2, function()
        activeRolls[rollID] = nil
    end)
end

function Tracker:GetActiveRoll(rollID)
    return activeRolls[rollID]
end

function Tracker:GetActiveRolls()
    return activeRolls
end

-- ============================================================================
-- Safety Timeout
-- Polls GetLootRollTimeLeft for rolls that LOOT_ROLLS_COMPLETE missed.
-- ============================================================================

local SAFETY_POLL_INTERVAL = 1  -- seconds
local SAFETY_GRACE = 3          -- seconds after timeLeft hits 0

local safetyFrame = CreateFrame("Frame")
local safetyElapsed = 0

safetyFrame:SetScript("OnUpdate", function(self, dt)
    safetyElapsed = safetyElapsed + dt
    if safetyElapsed < SAFETY_POLL_INTERVAL then return end
    safetyElapsed = 0

    local hasActive = false
    local now = GetTime()
    for rollID, rollData in pairs(activeRolls) do
        if not rollData.finished then
            hasActive = true
            local ok, timeLeft = pcall(GetLootRollTimeLeft, rollID)
            if not ok or timeLeft == 0 then
                if not rollData.expiredAt then
                    rollData.expiredAt = now
                elseif now - rollData.expiredAt > SAFETY_GRACE then
                    IT:Debug("Safety timeout: " .. rollData.itemLink)
                    Tracker:FinishRoll(rollID, nil)
                end
            end
        end
    end

    -- Only tick when there are active rolls
    if not hasActive then
        self:Hide()
    end
end)

safetyFrame:Hide()  -- starts hidden; enabled when a roll begins

-- ============================================================================
-- Module Interface
-- ============================================================================

function Tracker:Initialize()
    if not C_LootHistory then
        IT:Print("RollTracker: C_LootHistory unavailable — roll tracking disabled",
                 IT.Colors.error)
        return
    end

    IT:RegisterEvent("START_LOOT_ROLL", function(rollID, rollTime)
        OnStartLootRoll(rollID, rollTime)
        safetyFrame:Show()  -- activate polling while rolls are active
    end)
    IT:RegisterEvent("LOOT_HISTORY_ROLL_CHANGED", OnLootHistoryRollChanged)
    IT:RegisterEvent("LOOT_HISTORY_ROLL_COMPLETE", OnLootRollsComplete)
    IT:RegisterEvent("LOOT_ROLLS_COMPLETE", OnLootRollsComplete)
end
