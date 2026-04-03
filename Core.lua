--[[
    ItemTracker - TBC Anniversary Edition
    Core Module - Main addon framework and initialization

    This module handles:
    - Addon initialization and event registration
    - Global state management
    - Slash command handling
    - Module coordination
    - WoW event forwarding to modules via registration API
]]

local ADDON_NAME, IT = ...

-- Global addon namespace
ItemTracker = IT

-- ============================================================================
-- Container API Compatibility
-- TBC Anniversary uses C_Container namespace; Classic Era uses legacy globals.
-- ============================================================================

if not GetContainerNumSlots and C_Container then
    GetContainerNumSlots = C_Container.GetContainerNumSlots
    GetContainerItemLink = C_Container.GetContainerItemLink
    PickupContainerItem = C_Container.PickupContainerItem
    GetContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots
    UseContainerItem = C_Container.UseContainerItem
    GetContainerItemInfo = function(bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then return nil end
        return info.iconFileID, info.stackCount, info.isLocked, info.quality,
               info.isReadable, info.hasLoot, info.hyperlink, info.isFiltered,
               info.hasNoValue, info.itemID, info.isBound
    end
end

-- ============================================================================
-- Constants
-- ============================================================================

IT.VERSION = "0.2.1"
IT.BUILD = "TBC-Anniversary"

IT.QUALITY_POOR      = 0
IT.QUALITY_COMMON    = 1
IT.QUALITY_UNCOMMON  = 2
IT.QUALITY_RARE      = 3
IT.QUALITY_EPIC      = 4
IT.QUALITY_LEGENDARY = 5

IT.QUALITY_NAMES = {
    [0] = "Poor",
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
    [5] = "Legendary",
}

IT.QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },  -- Poor (gray)
    [1] = { r = 1.00, g = 1.00, b = 1.00 },  -- Common (white)
    [2] = { r = 0.12, g = 1.00, b = 0.00 },  -- Uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 },  -- Rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- Epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 },  -- Legendary (orange)
}

-- Color codes for chat messages
IT.Colors = {
    addon     = "|cFF00D1FF",
    success   = "|cFF00FF00",
    warning   = "|cFFFFFF00",
    error     = "|cFFFF0000",
    info      = "|cFFAAAAAA",
    highlight = "|cFFFFD700",
}

-- ============================================================================
-- SavedVariables Defaults
-- ============================================================================

local DB_DEFAULTS = {
    settings = {
        enabled             = true,
        soloQualityThreshold  = 2,   -- Uncommon (green) and above
        groupQualityThreshold = 2,   -- Uncommon (green) and above
        toastDuration       = 8,     -- seconds before toast fades
        toastMaxVisible     = 5,     -- max simultaneous toasts
        historySize         = 100,   -- max history entries kept
        locked              = false, -- lock bar position (hides bar when locked)
        toastUpward         = true,  -- true = toasts stack upward, false = downward
        position            = nil,   -- saved bar position {point, relativePoint, x, y}
        minimapAngle        = 225,   -- minimap button angle in degrees
        showMinimap         = true,
    },
    history = {},
}

local CHAR_DB_DEFAULTS = {}

-- ============================================================================
-- Addon State
-- ============================================================================

IT.initialized = false
IT.debugMode = false

-- ============================================================================
-- Event Bus (pub/sub for custom addon events)
-- Modules subscribe via IT.Events:Subscribe(); Core fires via IT.Events:Fire().
-- ============================================================================

local EventBus = {}
IT.Events = EventBus

local busListeners = {}

function EventBus:Subscribe(event, callback)
    if not busListeners[event] then
        busListeners[event] = {}
    end
    table.insert(busListeners[event], callback)
end

function EventBus:Fire(event, ...)
    if not busListeners[event] then return end
    for _, callback in ipairs(busListeners[event]) do
        callback(...)
    end
end

-- ============================================================================
-- WoW Event Registration API (Open/Closed Principle)
-- Modules call IT:RegisterEvent(event, callback) during Initialize().
-- Core dispatches without needing to know about module internals.
-- ============================================================================

local mainFrame = CreateFrame("Frame")
local coreHandlers = {}
local moduleHandlers = {}

function IT:RegisterEvent(event, callback)
    if not moduleHandlers[event] then
        moduleHandlers[event] = {}
        mainFrame:RegisterEvent(event)
    end
    table.insert(moduleHandlers[event], callback)
end

function IT:UnregisterEvent(event, callback)
    if not moduleHandlers[event] then return end
    for i, cb in ipairs(moduleHandlers[event]) do
        if cb == callback then
            table.remove(moduleHandlers[event], i)
            break
        end
    end
    if #moduleHandlers[event] == 0 and not coreHandlers[event] then
        mainFrame:UnregisterEvent(event)
        moduleHandlers[event] = nil
    end
end

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if coreHandlers[event] then
        coreHandlers[event](...)
    end
    if moduleHandlers[event] then
        for _, cb in ipairs(moduleHandlers[event]) do
            cb(...)
        end
    end
end)

-- ============================================================================
-- Utility Functions
-- ============================================================================

function IT:Print(msg, color)
    color = color or IT.Colors.addon
    DEFAULT_CHAT_FRAME:AddMessage(color .. "[ItemTracker]|r " .. msg)
end

function IT:Debug(msg)
    if IT.debugMode then
        IT:Print(msg, IT.Colors.info)
    end
end

function IT:GetItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

function IT:GetQualityColor(quality)
    local c = IT.QUALITY_COLORS[quality]
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

function IT:GetQualityHex(quality)
    local r, g, b = IT:GetQualityColor(quality)
    return string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
end

function IT:FormatTimeAgo(timestamp)
    local diff = GetTime() - timestamp
    if diff < 60 then
        return string.format("%ds ago", diff)
    elseif diff < 3600 then
        return string.format("%dm ago", diff / 60)
    else
        return string.format("%dh ago", diff / 3600)
    end
end

--- Convert a Blizzard format string (e.g. LOOT_ITEM) to a Lua pattern.
--- %s → (.+), %d → (%d+), other pattern-special characters are escaped.
function IT:FormatToPattern(fmt)
    -- Replace format specifiers with placeholders before escaping
    fmt = fmt:gsub("%%s", "\001")
    fmt = fmt:gsub("%%d", "\002")
    -- Escape Lua pattern magic characters
    fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    -- Restore placeholders as capture groups
    fmt = fmt:gsub("\001", "(.+)")
    fmt = fmt:gsub("\002", "(%%d+)")
    return "^" .. fmt .. "$"
end

-- ============================================================================
-- Deep-copy utility for defaults
-- ============================================================================

local function DeepCopyDefaults(defaults, target)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                DeepCopyDefaults(value, target[key])
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            DeepCopyDefaults(value, target[key])
        end
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

local function InitializeDB()
    if not ItemTrackerDB then
        ItemTrackerDB = {}
    end
    IT.db = ItemTrackerDB
    DeepCopyDefaults(DB_DEFAULTS, IT.db)

    if not ItemTrackerCharDB then
        ItemTrackerCharDB = {}
    end
    IT.charDB = ItemTrackerCharDB
    DeepCopyDefaults(CHAR_DB_DEFAULTS, IT.charDB)
end

local function InitializeModules()
    local moduleOrder = {}
    for key, mod in pairs(IT) do
        if type(mod) == "table" and type(mod.Initialize) == "function" then
            table.insert(moduleOrder, { name = key, mod = mod })
        end
    end
    table.sort(moduleOrder, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(moduleOrder) do
        local ok, err = pcall(entry.mod.Initialize, entry.mod)
        if not ok then
            IT:Print("Module '" .. entry.name .. "' failed to initialize: " .. tostring(err),
                     IT.Colors.error)
        end
    end
end

-- Core WoW event handlers
local coreEvents = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT" }
for _, event in ipairs(coreEvents) do
    mainFrame:RegisterEvent(event)
end

coreHandlers.ADDON_LOADED = function(addon)
    if addon ~= ADDON_NAME then return end
    InitializeDB()
    InitializeModules()
    IT.initialized = true
    IT:Debug("Addon loaded successfully (v" .. IT.VERSION .. ")")
end

coreHandlers.PLAYER_LOGIN = function()
    IT:Debug("Player login complete")
    IT.Events:Fire("PLAYER_READY")
end

coreHandlers.PLAYER_LOGOUT = function()
    IT.Events:Fire("PLAYER_LOGOUT")
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_ITEMTRACKER1 = "/itemtracker"
SLASH_ITEMTRACKER2 = "/it"

SlashCmdList["ITEMTRACKER"] = function(msg)
    msg = msg:trim():lower()

    if msg == "debug" then
        IT.debugMode = not IT.debugMode
        IT:Print("Debug mode: " .. (IT.debugMode and "ON" or "OFF"), IT.Colors.info)
    elseif msg == "version" then
        IT:Print("Version " .. IT.VERSION .. " (" .. IT.BUILD .. ")", IT.Colors.info)
    elseif msg == "config" or msg == "options" then
        if IT.Config and IT.Config.Toggle then
            IT.Config:Toggle()
        end
    elseif msg == "history" then
        if IT.UI and IT.UI.Toggle then
            IT.UI:Toggle()
        end
    elseif msg == "clear" then
        if IT.LootHistory then
            IT.LootHistory:Clear()
        end
        if IT.LootDetector and IT.LootDetector.ResetSessionGold then
            IT.LootDetector:ResetSessionGold()
        end
        IT:Print("Loot history and session gold cleared.", IT.Colors.success)
    elseif msg == "reset" then
        IT:Print("Use /it config to manage settings.", IT.Colors.info)
    elseif msg == "test" then
        IT:FireTestLoot()
    elseif msg == "test gold" then
        IT:FireTestGold()
    elseif msg == "test roll" then
        IT:FireTestRoll()
    elseif msg == "test lc" then
        IT:FireTestLC()
    elseif msg == "test reserve" then
        IT:FireTestReserve()
    elseif msg == "status" then
        IT:Print("Addon: " .. (IT.db.settings.enabled and "ON" or "OFF"), IT.Colors.info)
        IT:Print("RCLootCouncil: " .. (IT.RCLCIntegration and IT.RCLCIntegration:IsActive() and "active" or "not detected"), IT.Colors.info)
        IT:Print("LootReserve: " .. (IT.LRIntegration and IT.LRIntegration:IsActive() and "active" or "not detected"), IT.Colors.info)
        IT:Print("History: " .. (IT.LootHistory and IT.LootHistory:GetCount() or 0) .. " entries", IT.Colors.info)
    else
        IT:Print("Commands:", IT.Colors.highlight)
        IT:Print("  /it config    - Open settings", IT.Colors.info)
        IT:Print("  /it history   - Toggle history panel", IT.Colors.info)
        IT:Print("  /it clear     - Clear loot history", IT.Colors.info)
        IT:Print("  /it status    - Show integration status", IT.Colors.info)
        IT:Print("  /it test      - Simulate a loot drop", IT.Colors.info)
        IT:Print("  /it test roll - Simulate a group roll", IT.Colors.info)
        IT:Print("  /it test lc   - Simulate a loot council session", IT.Colors.info)
        IT:Print("  /it test reserve - Simulate a LootReserve roll", IT.Colors.info)
        IT:Print("  /it debug     - Toggle debug mode", IT.Colors.info)
        IT:Print("  /it version   - Show version", IT.Colors.info)
    end
end

-- ============================================================================
-- Test / Simulation
-- ============================================================================

local TEST_ITEMS = {
    { id = 28587, quality = 4, name = "Despair",                   icon = "Interface\\Icons\\INV_Sword_73" },
    { id = 28830, quality = 4, name = "Dragonspine Trophy",        icon = "Interface\\Icons\\INV_Trinket_Naxxramas06" },
    { id = 29434, quality = 3, name = "Badge of Justice",          icon = "Interface\\Icons\\INV_Jewelry_Talisman_08" },
    { id = 30311, quality = 4, name = "Warp Slicer",               icon = "Interface\\Icons\\INV_Sword_82" },
    { id = 28749, quality = 4, name = "King's Defender",           icon = "Interface\\Icons\\INV_Sword_79" },
    { id = 21877, quality = 2, name = "Netherweave Cloth",         icon = "Interface\\Icons\\INV_Fabric_Netherweave" },
    { id = 23077, quality = 1, name = "Blood Garnet",              icon = "Interface\\Icons\\INV_Jewelcrafting_BloodGarnet_01" },
    { id = 32428, quality = 5, name = "Ashes of Al'ar",            icon = "Interface\\Icons\\INV_Misc_Birdbeck_02" },
}

local testCounter = 0
local TEST_PLAYERS = { "Thrall", "Jaina", "Sylvanas", "Arthas", "Illidan" }

function IT:FireTestLoot()
    testCounter = testCounter + 1
    local item = TEST_ITEMS[(testCounter - 1) % #TEST_ITEMS + 1]
    local player = UnitName("player")
    local isSelf = true

    -- Alternate between self and fake group members
    if testCounter % 3 ~= 1 then
        player = TEST_PLAYERS[(testCounter - 1) % #TEST_PLAYERS + 1]
        isSelf = false
    end

    local fakeLink = "|cFF" .. string.format("%02X%02X%02X",
        IT.QUALITY_COLORS[item.quality].r * 255,
        IT.QUALITY_COLORS[item.quality].g * 255,
        IT.QUALITY_COLORS[item.quality].b * 255)
        .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"

    local entry = {
        itemLink    = fakeLink,
        itemID      = item.id,
        quality     = item.quality,
        count       = 1,
        player      = player,
        isSelf      = isSelf,
        isGroupLoot = not isSelf,
        timestamp   = GetTime(),
        icon        = item.icon,
    }

    IT:Print("Test loot: " .. fakeLink .. " by " .. player, IT.Colors.info)
    IT.Events:Fire("ITEM_LOOTED", entry)
end

function IT:FireTestRoll()
    testCounter = testCounter + 1
    local item = TEST_ITEMS[(testCounter - 1) % #TEST_ITEMS + 1]

    local fakeLink = "|cFF" .. string.format("%02X%02X%02X",
        IT.QUALITY_COLORS[item.quality].r * 255,
        IT.QUALITY_COLORS[item.quality].g * 255,
        IT.QUALITY_COLORS[item.quality].b * 255)
        .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"

    local rollID = 90000 + testCounter

    local rollData = {
        rollID    = rollID,
        itemLink  = fakeLink,
        itemID    = item.id,
        quality   = item.quality,
        icon      = item.icon,
        count     = 1,
        timeLeft  = 30,
        startTime = GetTime(),
        rolls     = {},
        winner    = nil,
        finished  = false,
    }

    IT:Print("Test roll started: " .. fakeLink, IT.Colors.info)
    IT.Events:Fire("ROLL_STARTED", rollData)

    -- Simulate rolls arriving over time
    local players = { "Thrall", "Jaina", "Sylvanas" }
    local types   = { "need", "greed", "pass" }
    for i, p in ipairs(players) do
        C_Timer.After(i * 1.2, function()
            local rollType = types[i]
            local num = (rollType ~= "pass") and math.random(1, 100) or 0
            local rollEntry = { player = p, rollType = rollType, number = num }
            table.insert(rollData.rolls, rollEntry)
            IT.Events:Fire("ROLL_UPDATE", rollID, rollEntry)
            IT:Print("  " .. p .. ": " .. rollType .. (num > 0 and (" " .. num) or ""), IT.Colors.info)
        end)
    end

    -- Simulate winner after all rolls
    C_Timer.After(#players * 1.2 + 1.5, function()
        -- Pick the highest need/greed roller as winner
        local winner = nil
        local best = -1
        for _, r in ipairs(rollData.rolls) do
            if r.number and r.number > best then
                best = r.number
                winner = r.player
            end
        end
        rollData.winner = winner
        rollData.finished = true
        IT:Print("  Winner: " .. (winner or "nobody"), IT.Colors.success)
        IT.Events:Fire("ROLL_ENDED", rollData)
    end)
end

function IT:FireTestLC()
    testCounter = testCounter + 1
    local item = TEST_ITEMS[(testCounter - 1) % #TEST_ITEMS + 1]
    local fakeLink = "|cFF" .. string.format("%02X%02X%02X",
        IT.QUALITY_COLORS[item.quality].r * 255,
        IT.QUALITY_COLORS[item.quality].g * 255,
        IT.QUALITY_COLORS[item.quality].b * 255)
        .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"

    local rollID = 100000 + testCounter
    local rollData = {
        rollID    = rollID,
        itemLink  = fakeLink,
        itemID    = item.id,
        quality   = item.quality,
        icon      = item.icon,
        count     = 1,
        timeLeft  = 0,
        startTime = GetTime(),
        rolls     = {},
        winner    = nil,
        finished  = false,
        source    = "RCLootCouncil",
    }

    IT:Print("Test LC session: " .. fakeLink, IT.Colors.info)
    IT.Events:Fire("ROLL_STARTED", rollData)

    -- Simulate council responses
    local voters = { "Thrall", "Jaina", "Sylvanas", "Arthas" }
    local responses = { "BIS", "Major Upgrade", "Minor Upgrade", "Offspec" }
    for i, v in ipairs(voters) do
        C_Timer.After(i * 0.8, function()
            table.insert(rollData.rolls, { player = v, rollType = responses[i], number = 0 })
            IT.Events:Fire("ROLL_UPDATE", rollID, rollData.rolls[#rollData.rolls])
            IT:Print("  " .. v .. ": " .. responses[i], IT.Colors.info)
        end)
    end

    -- Award after council votes
    C_Timer.After(#voters * 0.8 + 2, function()
        local winner = "Thrall"
        rollData.winner = winner
        rollData.finished = true
        rollData.rolls = {{ player = winner, rollType = "council", number = 0 }}
        IT:Print("  Council awarded to: " .. winner, IT.Colors.success)
        IT.Events:Fire("ROLL_ENDED", rollData)
    end)
end

function IT:FireTestReserve()
    testCounter = testCounter + 1
    local item = TEST_ITEMS[(testCounter - 1) % #TEST_ITEMS + 1]
    local fakeLink = "|cFF" .. string.format("%02X%02X%02X",
        IT.QUALITY_COLORS[item.quality].r * 255,
        IT.QUALITY_COLORS[item.quality].g * 255,
        IT.QUALITY_COLORS[item.quality].b * 255)
        .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"

    local rollID = 200000 + testCounter
    -- Show who reserved this item
    local reservers = { "Jaina", "Arthas" }
    local rollEntries = {}
    for _, p in ipairs(reservers) do
        table.insert(rollEntries, { player = p, rollType = "reserve", number = 0 })
    end

    local rollData = {
        rollID    = rollID,
        itemLink  = fakeLink,
        itemID    = item.id,
        quality   = item.quality,
        icon      = item.icon,
        count     = 1,
        timeLeft  = 0,
        startTime = GetTime(),
        rolls     = rollEntries,
        winner    = nil,
        finished  = false,
        source    = "LootReserve",
    }

    IT:Print("Test reserve roll: " .. fakeLink .. " (reserved by " .. table.concat(reservers, ", ") .. ")", IT.Colors.info)
    IT.Events:Fire("ROLL_STARTED", rollData)

    -- Simulate rolls
    C_Timer.After(1.5, function()
        rollData.rolls[1].number = math.random(1, 100)
        IT.Events:Fire("ROLL_UPDATE", rollID, rollData.rolls[1])
        IT:Print("  " .. reservers[1] .. " rolls " .. rollData.rolls[1].number, IT.Colors.info)
    end)

    C_Timer.After(3, function()
        rollData.rolls[2].number = math.random(1, 100)
        IT.Events:Fire("ROLL_UPDATE", rollID, rollData.rolls[2])
        IT:Print("  " .. reservers[2] .. " rolls " .. rollData.rolls[2].number, IT.Colors.info)
    end)

    -- Winner
    C_Timer.After(4.5, function()
        local winner = rollData.rolls[1].number > rollData.rolls[2].number and reservers[1] or reservers[2]
        rollData.winner = winner
        rollData.finished = true
        IT:Print("  Winner: " .. winner, IT.Colors.success)
        IT.Events:Fire("ROLL_ENDED", rollData)
    end)
end

function IT:FireTestGold()
    if IT.LootDetector and IT.LootDetector._addTestGold then
        local copper = math.random(10000, 250000)
        IT.LootDetector._addTestGold(copper)
        local gold   = math.floor(copper / 10000)
        local silver = math.floor((copper % 10000) / 100)
        local cop    = copper % 100
        local parts = {}
        if gold > 0 then table.insert(parts, gold .. "g") end
        if silver > 0 then table.insert(parts, silver .. "s") end
        if cop > 0 then table.insert(parts, cop .. "c") end
        IT:Print("Test gold: +" .. table.concat(parts, " "), IT.Colors.highlight)
    end
end
