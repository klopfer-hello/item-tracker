--[[
    ItemTracker - GearGoalsDetector Module
    Single Responsibility: Match incoming loot / chat events against the
    active goal set and fire GEAR_GOAL_DROPPED on the bus once per
    (itemID, dedup-scope).

    Two detection sources, deduped against each other:
      1. ITEM_LOOTED from LootDetector (group/raid/solo loot, locale-safe).
      2. Item links in party / raid / whisper chat channels — scanned by
         pulling all item:N hyperlinks out of the message and matching
         each against the active goal set.

    Dedup state lives in GearGoals (cleared on group-leave or zone change).

    Fires:
      GEAR_GOAL_DROPPED  with payload:
        {
          itemID, itemLink, slotID, looter, fromChat,
          matches = { { specKey, phase, slotID, rank, isMainSpec }, ... },
        }
      `matches` only contains entries that pass the rank-suppression rule.
]]

local _, IT = ...
local Detector = {}
IT.GearGoalsDetector = Detector

-- ============================================================================
-- Match against the goal set
-- ============================================================================

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- Resolve all goal matches for an itemID *that are eligible to notify*
--- given the current phase and the rank-suppression rule.
---
--- Two paths:
---   1. Direct match: dropped itemID is itself the goal item.
---   2. Token redemption: dropped itemID is a class-token (e.g. Helm of the
---      Fallen Hero) whose redemption list contains the goal item.
---
--- Each result entry:
---   { specKey, phase, slotID, rank, isMainSpec, isToken, goalItemID }
local function CollectEligibleMatches(itemID)
    local GG = IT.GearGoals
    if not GG or not GG.FindAllMatches then return {} end

    local mainLoadout   = GG:GetMainLoadoutID()
    local currentPhase  = GG:GetCurrentPhase()
    local out           = {}

    local function tryGoal(rawMatch, goalItemID, isToken)
        local phaseAllowed = (rawMatch.phase == currentPhase) or (rawMatch.phase == "pre-raid")
        if not phaseAllowed then return end
        if not GG:CanNotify(rawMatch.specKey, rawMatch.phase, rawMatch.slotID, rawMatch.rank) then return end
        table.insert(out, {
            loadoutID  = rawMatch.specKey,         -- specKey was renamed; field name is now loadoutID
            specKey    = rawMatch.specKey,         -- alias kept for the popup compatibility
            phase      = rawMatch.phase,
            slotID     = rawMatch.slotID,
            rank       = rawMatch.rank,
            isMain     = (rawMatch.specKey == mainLoadout),
            isMainSpec = (rawMatch.specKey == mainLoadout),  -- legacy alias
            isToken    = isToken or false,
            goalItemID = goalItemID,
        })
    end

    -- Direct match
    for _, m in ipairs(GG:FindAllMatches(itemID)) do
        tryGoal(m, itemID, false)
    end

    -- Token expansion: if itemID is a known token, walk each class-specific
    -- item it redeems for and look that up against goals.
    local Tokens = IT.GearGoalsTokens
    if Tokens and Tokens:IsToken(itemID) then
        local redemptions = Tokens:GetRedemptions(itemID)
        if redemptions then
            for _, classItemID in ipairs(redemptions) do
                for _, m in ipairs(GG:FindAllMatches(classItemID)) do
                    tryGoal(m, classItemID, true)
                end
            end
        end
    end

    return out
end

local function FireDrop(itemID, itemLink, looter, fromChat)
    local GG = IT.GearGoals
    if not GG then return end
    if GG:HasSeen(itemID) then return end                 -- dedup

    local matches = CollectEligibleMatches(itemID)
    if #matches == 0 then return end

    GG:MarkSeen(itemID)

    IT.Events:Fire("GEAR_GOAL_DROPPED", {
        itemID   = itemID,
        itemLink = itemLink,
        slotID   = matches[1].slotID,
        looter   = looter,
        fromChat = fromChat and true or false,
        matches  = matches,
    })
end

-- ============================================================================
-- Source 1: ITEM_LOOTED (corpse loot, observed via LootDetector)
-- ============================================================================

local function OnItemLooted(entry)
    if not entry or not entry.itemID then return end
    -- Feed every observed loot into the autocomplete cache so quest-reward
    -- and crafted items become searchable even if AtlasLoot doesn't know them.
    if IT.GearGoals and IT.GearGoals.RememberItem then
        IT.GearGoals:RememberItem(entry.itemID)
    end
    FireDrop(entry.itemID, entry.itemLink, entry.player, false)
end

-- ============================================================================
-- Source 2: Chat scan
-- Scans party/raid/whisper messages for any item:N hyperlink. Channels are
-- intentionally narrow — public channels and guild are excluded to avoid
-- noise from unrelated shares.
-- ============================================================================

local CHAT_EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
}

local function OnChatMsg(msg, sender)
    if not msg then return end
    -- Walk every item link in the message
    for link in msg:gmatch("|c%x+|Hitem:%d+:[%-?%d:]*|h%[[^%]]+%]|h|r") do
        local itemID = ItemIDFromLink(link)
        if itemID then
            -- Feed into the autocomplete cache regardless of goal-match
            if IT.GearGoals and IT.GearGoals.RememberItem then
                IT.GearGoals:RememberItem(itemID)
            end
            FireDrop(itemID, link, sender, true)
        end
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Detector:Initialize()
    IT.Events:Subscribe("ITEM_LOOTED", OnItemLooted)
    for _, evt in ipairs(CHAT_EVENTS) do
        IT:RegisterEvent(evt, OnChatMsg)
    end
    IT:Debug("GearGoalsDetector initialized")
end
