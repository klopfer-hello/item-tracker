--[[
    ItemTracker - RollTracker Module
    Single Responsibility: Track group loot rolls (Need/Greed/Pass),
    maintain per-item roll state, and fire roll lifecycle events.

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
-- Locale-safe Roll Message Patterns
-- ============================================================================

local rollPatterns  -- built lazily

local function BuildRollPatterns()
    local fmt = IT.FormatToPattern

    rollPatterns = {}

    -- Need/Greed/Disenchant roll results: "%s Need Roll - %d for: %s"
    if LOOT_ROLL_NEED then
        rollPatterns.need = fmt(IT, LOOT_ROLL_NEED)
    end
    if LOOT_ROLL_NEED_SELF then
        rollPatterns.needSelf = fmt(IT, LOOT_ROLL_NEED_SELF)
    end
    if LOOT_ROLL_GREED then
        rollPatterns.greed = fmt(IT, LOOT_ROLL_GREED)
    end
    if LOOT_ROLL_GREED_SELF then
        rollPatterns.greedSelf = fmt(IT, LOOT_ROLL_GREED_SELF)
    end
    if LOOT_ROLL_DISENCHANT then
        rollPatterns.disenchant = fmt(IT, LOOT_ROLL_DISENCHANT)
    end
    if LOOT_ROLL_DISENCHANT_SELF then
        rollPatterns.disenchantSelf = fmt(IT, LOOT_ROLL_DISENCHANT_SELF)
    end

    -- Pass patterns: "%s passed on: %s"
    if LOOT_ROLL_PASSED then
        rollPatterns.passed = fmt(IT, LOOT_ROLL_PASSED)
    end
    if LOOT_ROLL_PASSED_SELF then
        rollPatterns.passedSelf = fmt(IT, LOOT_ROLL_PASSED_SELF)
    end
    if LOOT_ROLL_PASSED_AUTO then
        rollPatterns.passedAuto = fmt(IT, LOOT_ROLL_PASSED_AUTO)
    end
    if LOOT_ROLL_PASSED_AUTO_FEMALE then
        rollPatterns.passedAutoFemale = fmt(IT, LOOT_ROLL_PASSED_AUTO_FEMALE)
    end

    -- Won patterns: "%s won: %s"
    if LOOT_ROLL_WON then
        rollPatterns.won = fmt(IT, LOOT_ROLL_WON)
    end
    if LOOT_ROLL_ALL_PASSED then
        rollPatterns.allPassed = fmt(IT, LOOT_ROLL_ALL_PASSED)
    end
end

-- ============================================================================
-- Roll Start (WoW event)
-- ============================================================================

local function OnStartLootRoll(rollID, rollTime)
    if not IT.db.settings.enabled then return end

    local texture, name, count, quality, bindOnPickUp, canNeed, canGreed, canDisenchant
        = GetLootRollItemInfo(rollID)
    local itemLink = GetLootRollItemLink(rollID)
    if not itemLink then return end

    local isGroupLoot = true
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
-- Roll Message Parsing (system chat messages)
-- ============================================================================

--- Identify captures by content, not position (locale-safe).
--- %d captures are pure digits; item links contain "|H"; the rest is a player name.
local function ClassifyCaptures(captures)
    local player, num, link
    for _, cap in ipairs(captures) do
        if not num and cap:match("^%d+$") then
            num = tonumber(cap)
        elseif not link and cap:find("|H") then
            link = cap
        else
            player = player or cap
        end
    end
    return player, num, link
end

local function TryMatchRoll(msg, pattern, rollType, isSelf)
    if not pattern then return nil end
    local captures = {msg:match(pattern)}
    if #captures == 0 then return nil end

    if isSelf then
        local _, num, link = ClassifyCaptures(captures)
        if num then
            return UnitName("player"), rollType, num, link
        end
    else
        local player, num, link = ClassifyCaptures(captures)
        if player and num then
            return player, rollType, num, link
        end
    end
    return nil
end

local function TryMatchPass(msg, pattern, isSelf)
    if not pattern then return nil end
    local captures = {msg:match(pattern)}
    if #captures == 0 then return nil end

    if isSelf then
        return UnitName("player"), "pass", 0, captures[1]
    else
        local player, _, link = ClassifyCaptures(captures)
        if player then
            return player, "pass", 0, link
        end
    end
    return nil
end

local function TryMatchWon(msg)
    if not rollPatterns or not rollPatterns.won then return nil end
    local captures = {msg:match(rollPatterns.won)}
    if #captures < 2 then return nil end

    local player, _, link = ClassifyCaptures(captures)
    if player and link then
        return player, link
    end
    return nil
end

local function TryMatchAllPassed(msg)
    if not rollPatterns or not rollPatterns.allPassed then return nil end
    local link = msg:match(rollPatterns.allPassed)
    return link
end

--- Find the active rollData that matches an item link.
local function FindRollByItemLink(link)
    if not link then return nil, nil end
    local targetID = IT:GetItemIDFromLink(link)
    if not targetID then return nil, nil end
    for rollID, data in pairs(activeRolls) do
        if data.itemID == targetID and not data.finished then
            return rollID, data
        end
    end
    return nil, nil
end

local function ParseRollMessage(msg)
    if not rollPatterns then return end

    -- Try numbered roll patterns (need/greed/disenchant)
    local player, rollType, num, link
    player, rollType, num, link = TryMatchRoll(msg, rollPatterns.needSelf, "need", true)
    if not player then player, rollType, num, link = TryMatchRoll(msg, rollPatterns.need, "need", false) end
    if not player then player, rollType, num, link = TryMatchRoll(msg, rollPatterns.greedSelf, "greed", true) end
    if not player then player, rollType, num, link = TryMatchRoll(msg, rollPatterns.greed, "greed", false) end
    if not player then player, rollType, num, link = TryMatchRoll(msg, rollPatterns.disenchantSelf, "disenchant", true) end
    if not player then player, rollType, num, link = TryMatchRoll(msg, rollPatterns.disenchant, "disenchant", false) end

    -- Try pass patterns
    if not player then player, rollType, num, link = TryMatchPass(msg, rollPatterns.passedSelf, true) end
    if not player then player, rollType, num, link = TryMatchPass(msg, rollPatterns.passed, false) end
    if not player then player, rollType, num, link = TryMatchPass(msg, rollPatterns.passedAuto, false) end
    if not player then player, rollType, num, link = TryMatchPass(msg, rollPatterns.passedAutoFemale, false) end

    if player and link then
        local rollID, rollData = FindRollByItemLink(link)
        if rollData then
            local entry = { player = player, rollType = rollType, number = num }
            table.insert(rollData.rolls, entry)
            IT:Debug("Roll update: " .. player .. " " .. rollType .. " " .. (num or 0))
            IT.Events:Fire("ROLL_UPDATE", rollID, entry)
        end
        return
    end

    -- Try won pattern
    local winner, wonLink = TryMatchWon(msg)
    if winner and wonLink then
        local rollID, rollData = FindRollByItemLink(wonLink)
        if rollData then
            Tracker:FinishRoll(rollID, winner)
        end
        return
    end

    -- Try all-passed pattern
    local passedLink = TryMatchAllPassed(msg)
    if passedLink then
        local rollID, rollData = FindRollByItemLink(passedLink)
        if rollData then
            Tracker:FinishRoll(rollID, nil)
        end
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
-- Cancel / Timeout
-- ============================================================================

local CANCEL_GRACE_PERIOD = 5  -- seconds; wait for chat messages before treating as cancelled

local function OnCancelLootRoll(rollID)
    local rollData = activeRolls[rollID]
    if not rollData or rollData.finished then return end

    -- CANCEL_LOOT_ROLL fires when our roll frame closes (i.e. the moment we
    -- click Need/Greed/Pass), NOT when the group roll resolves.  Delay cleanup
    -- so that result chat messages (individual rolls + winner) have time to
    -- arrive and resolve the roll properly.
    C_Timer.After(CANCEL_GRACE_PERIOD, function()
        if not rollData.finished then
            Tracker:FinishRoll(rollID, nil)
        end
    end)
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function Tracker:Initialize()
    BuildRollPatterns()
    IT:RegisterEvent("START_LOOT_ROLL", OnStartLootRoll)
    IT:RegisterEvent("CANCEL_LOOT_ROLL", OnCancelLootRoll)
    IT:RegisterEvent("CHAT_MSG_LOOT", function(msg) ParseRollMessage(msg) end)
end
