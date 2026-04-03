--[[
    ItemTracker - RCLootCouncil Integration
    Single Responsibility: Detect RCLootCouncil sessions and awards,
    translate them into the ROLL_STARTED / ROLL_ENDED event protocol
    so Toast and LootHistory work without modification.

    Hook points (all fire on every client, not just ML):
      - RC:OnLootTableReceived() → items enter voting → ROLL_STARTED
      - RC:GetLootTable()[session].awarded → item awarded → ROLL_ENDED
      - Also listens for RCMLAwardSuccess (ML client only, bonus)

    Safe: does nothing if RCLootCouncil is not installed.
]]

local _, IT = ...
local RCLC = {}
IT.RCLCIntegration = RCLC

-- ============================================================================
-- Constants
-- ============================================================================

local ROLL_ID_BASE = 100000  -- offset to avoid collisions with native rollIDs
local RC_ADDON_NAMES = { "RCLootCouncil_Classic", "RCLootCouncil" }

-- ============================================================================
-- State
-- ============================================================================

local hooked = false
local activeSessions = {}  -- session → rollData

-- ============================================================================
-- Helpers
-- ============================================================================

local function IsRCLoaded()
    for _, name in ipairs(RC_ADDON_NAMES) do
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) then
            return true
        elseif IsAddOnLoaded and IsAddOnLoaded(name) then
            return true
        end
    end
    return false
end

local function GetRC()
    if not LibStub then return nil end
    local ok, rc = pcall(LibStub, "AceAddon-3.0")
    if not ok or not rc then return nil end
    local ok2, addon = pcall(rc.GetAddon, rc, "RCLootCouncil")
    if not ok2 then return nil end
    return addon
end

-- ============================================================================
-- Session Tracking
-- ============================================================================

local function OnLootTableReceived(rc)
    local lt = rc:GetLootTable()
    if not lt then return end

    for session, entry in ipairs(lt) do
        if entry.link and not activeSessions[session] then
            local itemID = IT:GetItemIDFromLink(entry.link)
            local rollID = ROLL_ID_BASE + session

            local rollData = {
                rollID    = rollID,
                itemLink  = entry.link,
                itemID    = itemID,
                quality   = entry.quality or select(3, GetItemInfo(entry.link)) or 4,
                icon      = entry.texture or select(10, GetItemInfo(entry.link)),
                count     = 1,
                timeLeft  = 0,
                startTime = GetTime(),
                rolls     = {},
                winner    = nil,
                finished  = false,
                source    = "RCLootCouncil",
            }

            activeSessions[session] = rollData
            IT:Debug("RCLC session item: " .. entry.link)
            IT.Events:Fire("ROLL_STARTED", rollData)
        end
    end
end

local function OnItemAwarded(session, winner)
    local rollData = activeSessions[session]
    if not rollData or rollData.finished then return end

    rollData.finished = true
    rollData.winner = winner
    rollData.rolls = {{ player = winner or "?", rollType = "council", number = 0 }}

    IT:Debug("RCLC award: session " .. session .. " to " .. (winner or "?"))
    IT.Events:Fire("ROLL_ENDED", rollData)

    C_Timer.After(2, function()
        activeSessions[session] = nil
    end)
end

-- ============================================================================
-- Hook Installation
-- ============================================================================

local function InstallHooks()
    if hooked then return end

    local RC = GetRC()
    if not RC then return end

    -- Hook OnLootTableReceived (fires on all clients when ML sends loot table)
    if RC.OnLootTableReceived then
        hooksecurefunc(RC, "OnLootTableReceived", function(self)
            local ok, err = pcall(OnLootTableReceived, self)
            if not ok then IT:Debug("RCLC lootTable hook error: " .. tostring(err)) end
        end)
        IT:Debug("RCLC: hooked OnLootTableReceived")
    end

    -- Hook voting frame's OnAwardedReceived (fires on all clients)
    local ok, VF = pcall(function() return RC:GetModule("RCVotingFrame") end)
    if ok and VF and VF.OnAwardedReceived then
        hooksecurefunc(VF, "OnAwardedReceived", function(self, session, winner)
            local ok2, err = pcall(OnItemAwarded, session, winner)
            if not ok2 then IT:Debug("RCLC award hook error: " .. tostring(err)) end
        end)
        IT:Debug("RCLC: hooked OnAwardedReceived")
    end

    -- Also listen for RCMLAwardSuccess (ML client only, as bonus)
    if RC.RegisterMessage then
        RC:RegisterMessage("RCMLAwardSuccess", function(_, session, winner, status, link)
            if not activeSessions[session] then
                -- ML might see this before OnLootTableReceived fired the ROLL
                -- Just record it for history via ITEM_LOOTED (LootDetector handles it)
                return
            end
            pcall(OnItemAwarded, session, winner)
        end)
        IT:Debug("RCLC: registered RCMLAwardSuccess")
    end

    -- Clean up when session ends
    if RC.RegisterMessage then
        RC:RegisterMessage("RCSessionEnd", function()
            -- Finish any unfinished sessions
            for session, rollData in pairs(activeSessions) do
                if not rollData.finished then
                    rollData.finished = true
                    IT.Events:Fire("ROLL_ENDED", rollData)
                end
            end
            wipe(activeSessions)
        end)
    end

    hooked = true
    IT:Print("RCLootCouncil integration active", IT.Colors.success)
end

-- ============================================================================
-- Public API
-- ============================================================================

function RCLC:IsActive()
    return hooked
end

function RCLC:GetActiveSession(session)
    return activeSessions[session]
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function RCLC:Initialize()
    if IsRCLoaded() then
        -- RC already loaded, hook now (with slight delay for RC to finish init)
        C_Timer.After(1, InstallHooks)
    else
        -- Wait for RC to load
        IT:RegisterEvent("ADDON_LOADED", function(addon)
            for _, name in ipairs(RC_ADDON_NAMES) do
                if addon == name then
                    C_Timer.After(1, InstallHooks)
                    return
                end
            end
        end)
    end
end
