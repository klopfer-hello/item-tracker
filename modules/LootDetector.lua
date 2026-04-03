--[[
    ItemTracker - LootDetector Module
    Single Responsibility: Detect loot events from CHAT_MSG_LOOT,
    filter by quality threshold, and fire ITEM_LOOTED on the event bus.

    Does NOT store data or create UI — downstream modules handle that.
]]

local _, IT = ...
local Detector = {}
IT.LootDetector = Detector

-- ============================================================================
-- Locale-safe Loot Message Patterns
-- Built from Blizzard global strings so they work on any client language.
-- ============================================================================

local patterns -- built lazily after globals are available

local function BuildPatterns()
    local fmt = IT.FormatToPattern
    patterns = {
        selfMulti  = fmt(IT, LOOT_ITEM_SELF_MULTIPLE),  -- "You receive loot: %sx%d."
        self       = fmt(IT, LOOT_ITEM_SELF),            -- "You receive loot: %s."
        otherMulti = fmt(IT, LOOT_ITEM_MULTIPLE),        -- "%s receives loot: %sx%d."
        other      = fmt(IT, LOOT_ITEM),                 -- "%s receives loot: %s."
    }
end

-- ============================================================================
-- Message Parsing
-- ============================================================================

--- Parse a CHAT_MSG_LOOT message into player, itemLink, count.
--- Returns nil if the message does not match any known loot pattern.
function Detector:ParseLootMessage(msg)
    if not patterns then BuildPatterns() end

    -- Self with quantity (must be tested before self-single to avoid greedy match)
    local link, count = msg:match(patterns.selfMulti)
    if link then
        return UnitName("player"), link, tonumber(count)
    end

    -- Self single
    link = msg:match(patterns.self)
    if link then
        return UnitName("player"), link, 1
    end

    -- Other player with quantity
    local player
    player, link, count = msg:match(patterns.otherMulti)
    if player and link then
        return player, link, tonumber(count)
    end

    -- Other player single
    player, link = msg:match(patterns.other)
    if player and link then
        return player, link, 1
    end

    return nil, nil, nil
end

-- ============================================================================
-- Quality Gate
-- ============================================================================

local function PassesQualityThreshold(quality, isGroupLoot)
    local threshold = isGroupLoot
        and IT.db.settings.groupQualityThreshold
        or  IT.db.settings.soloQualityThreshold
    return quality and quality >= threshold
end

-- ============================================================================
-- Event Handler
-- ============================================================================

local function OnChatMsgLoot(msg)
    if not IT.db.settings.enabled then return end

    local player, itemLink, count = Detector:ParseLootMessage(msg)
    if not player or not itemLink then return end

    local itemID = IT:GetItemIDFromLink(itemLink)
    if not itemID then return end

    local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemLink)
    local isGroupLoot = IsInGroup() or IsInRaid()
    local isSelf = (player == UnitName("player"))

    -- In solo mode only show own loot; in group mode show everyone's
    if not isGroupLoot and not isSelf then return end

    if not PassesQualityThreshold(quality, isGroupLoot) then return end

    local entry = {
        itemLink    = itemLink,
        itemID      = itemID,
        quality     = quality or 0,
        count       = count or 1,
        player      = player,
        isSelf      = isSelf,
        isGroupLoot = isGroupLoot,
        timestamp   = GetTime(),
        icon        = icon,
    }

    IT:Debug("Loot detected: " .. itemLink .. " x" .. entry.count .. " by " .. player)
    IT.Events:Fire("ITEM_LOOTED", entry)
end

-- ============================================================================
-- Quest Reward Detection
-- CHAT_MSG_LOOT does not fire for quest rewards from NPCs.
-- QUEST_LOOT_RECEIVED(questID, itemLink, count) fires in TBC Classic.
-- Fallback: CHAT_MSG_SYSTEM with LOOT_ITEM_PUSHED_SELF pattern.
-- ============================================================================

local function OnQuestLootReceived(questID, itemLink, count)
    if not IT.db.settings.enabled then return end
    if not itemLink then return end

    local itemID = IT:GetItemIDFromLink(itemLink)
    if not itemID then return end

    local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemLink)
    local isGroupLoot = IsInGroup() or IsInRaid()

    if not PassesQualityThreshold(quality, isGroupLoot) then return end

    local entry = {
        itemLink    = itemLink,
        itemID      = itemID,
        quality     = quality or 0,
        count       = count or 1,
        player      = UnitName("player"),
        isSelf      = true,
        isGroupLoot = isGroupLoot,
        timestamp   = GetTime(),
        icon        = icon,
    }

    IT:Debug("Quest loot detected: " .. itemLink)
    IT.Events:Fire("ITEM_LOOTED", entry)
end

--- Fallback: items pushed to bags (quest rewards, mail, etc.)
--- Uses LOOT_ITEM_PUSHED_SELF / LOOT_ITEM_PUSHED_SELF_MULTIPLE global strings.
local pushPatterns

local function BuildPushPatterns()
    local fmt = IT.FormatToPattern
    pushPatterns = {}
    if LOOT_ITEM_PUSHED_SELF_MULTIPLE then
        pushPatterns.selfMulti = fmt(IT, LOOT_ITEM_PUSHED_SELF_MULTIPLE)
    end
    if LOOT_ITEM_PUSHED_SELF then
        pushPatterns.self = fmt(IT, LOOT_ITEM_PUSHED_SELF)
    end
end

local function OnChatMsgSystem(msg)
    if not IT.db.settings.enabled then return end
    if not pushPatterns then BuildPushPatterns() end

    local link, count
    if pushPatterns.selfMulti then
        link, count = msg:match(pushPatterns.selfMulti)
        if link then count = tonumber(count) end
    end
    if not link and pushPatterns.self then
        link = msg:match(pushPatterns.self)
        if link then count = 1 end
    end
    if not link then return end

    local itemID = IT:GetItemIDFromLink(link)
    if not itemID then return end

    local _, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link)
    local isGroupLoot = IsInGroup() or IsInRaid()

    if not PassesQualityThreshold(quality, isGroupLoot) then return end

    local entry = {
        itemLink    = link,
        itemID      = itemID,
        quality     = quality or 0,
        count       = count or 1,
        player      = UnitName("player"),
        isSelf      = true,
        isGroupLoot = isGroupLoot,
        timestamp   = GetTime(),
        icon        = icon,
    }

    IT:Debug("Pushed loot detected: " .. link)
    IT.Events:Fire("ITEM_LOOTED", entry)
end

-- ============================================================================
-- Gold Tracking
-- Session-only (not persisted). Fires GOLD_LOOTED for UI display.
-- ============================================================================

local sessionCopper = 0

--- Parse a CHAT_MSG_MONEY message into copper value.
--- Uses GOLD_AMOUNT / SILVER_AMOUNT / COPPER_AMOUNT globals which are
--- localized format strings like "%d Gold" → convert to "(%d+) Gold" pattern.
local moneyPatterns

local function BuildMoneyPatterns()
    moneyPatterns = {}
    -- GOLD_AMOUNT = "%d Gold" → "(%d+) Gold"
    if GOLD_AMOUNT then
        moneyPatterns.gold = GOLD_AMOUNT:gsub("%%d", "(%%d+)")
    end
    if SILVER_AMOUNT then
        moneyPatterns.silver = SILVER_AMOUNT:gsub("%%d", "(%%d+)")
    end
    if COPPER_AMOUNT then
        moneyPatterns.copper = COPPER_AMOUNT:gsub("%%d", "(%%d+)")
    end
end

local function ParseMoneyMessage(msg)
    if not moneyPatterns then BuildMoneyPatterns() end

    local copper = 0
    if moneyPatterns.gold then
        local g = msg:match(moneyPatterns.gold)
        if g then copper = copper + tonumber(g) * 10000 end
    end
    if moneyPatterns.silver then
        local s = msg:match(moneyPatterns.silver)
        if s then copper = copper + tonumber(s) * 100 end
    end
    if moneyPatterns.copper then
        local c = msg:match(moneyPatterns.copper)
        if c then copper = copper + tonumber(c) end
    end

    return copper
end

local function OnChatMsgMoney(msg)
    if not IT.db.settings.enabled then return end
    local copper = ParseMoneyMessage(msg)
    if copper > 0 then
        sessionCopper = sessionCopper + copper
        IT.Events:Fire("GOLD_LOOTED", sessionCopper)
        if IT.db.settings.toastGold then
            IT.Events:Fire("GOLD_DROP", copper)
        end
    end
end

function Detector:GetSessionGold()
    return sessionCopper
end

function Detector:ResetSessionGold()
    sessionCopper = 0
    IT.Events:Fire("GOLD_LOOTED", 0)
end

-- Test helper: add copper directly (used by /it test gold)
function Detector._addTestGold(copper)
    sessionCopper = sessionCopper + copper
    IT.Events:Fire("GOLD_LOOTED", sessionCopper)
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function Detector:Initialize()
    IT:RegisterEvent("CHAT_MSG_LOOT", OnChatMsgLoot)
    IT:RegisterEvent("CHAT_MSG_MONEY", OnChatMsgMoney)
    -- Quest rewards (TBC Classic Anniversary)
    IT:RegisterEvent("QUEST_LOOT_RECEIVED", function(...)
        local ok, err = pcall(OnQuestLootReceived, ...)
        if not ok then IT:Debug("QUEST_LOOT_RECEIVED error: " .. tostring(err)) end
    end)
    -- Fallback: items pushed to bags (quest rewards on older clients, mail, etc.)
    IT:RegisterEvent("CHAT_MSG_SYSTEM", OnChatMsgSystem)
end
