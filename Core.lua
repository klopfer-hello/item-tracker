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

-- Read straight from the TOC so the reported version can never drift from
-- the packaged one (it sat at 0.6.0 through two releases).
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
IT.VERSION = GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version") or "0.8.0"
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

-- Color codes for chat messages. `addon` is the brand gold used for
-- chat output; matches the dark/gold UI palette in modules/Theme.lua.
IT.Colors = {
    addon     = "|cFFFFCC33",
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
        toastGold           = false, -- show toast for gold loot
        position            = nil,   -- saved bar position {point, relativePoint, x, y}
        minimapAngle        = 225,   -- minimap button angle in degrees
        showMinimap         = true,
        chatOutput          = true,  -- print messages to chat frame

        -- Scrolling loot text (modules/LootText.lua). Independent of the
        -- history quality thresholds above: this shows EVERYTHING looted
        -- (via ITEM_VALUE) and never writes to the history table.
        lootTextEnable      = true,  -- master switch for the scrolling text
        lootTextShowItems   = true,  -- scroll looted items
        lootTextShowMoney   = true,  -- scroll looted money (per-drop)
        lootTextQuality     = 0,     -- display-only floor; 0 = show everything
        lootTextScale       = 1.0,   -- font scale
        lootTextDuration    = 3,     -- seconds each line stays on screen
        lootTextUp          = true,  -- true = drift upward, false = downward
        lootTextPos         = nil,   -- {x, y} offset from UIParent centre
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
        local ok, err = pcall(callback, ...)
        if not ok then
            IT:Debug("EventBus error in " .. event .. ": " .. tostring(err))
        end
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
            local ok, err = pcall(cb, ...)
            if not ok then
                IT:Debug("Event handler error in " .. event .. ": " .. tostring(err))
            end
        end
    end
end)

-- ============================================================================
-- Utility Functions
-- ============================================================================

function IT:Print(msg, color)
    if IT.db and IT.db.settings and not IT.db.settings.chatOutput then return end
    color = color or IT.Colors.addon
    DEFAULT_CHAT_FRAME:AddMessage(color .. "[KIT]|r " .. msg)
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

--- Render a "X ago" relative time. Expects an epoch timestamp from `time()`.
--- Defensive against nil and against legacy session-time stamps left over
--- from the old GetTime()-based history. Unknown / unreadable timestamps
--- render as an em-dash so the column reads "no data" rather than broken.
function IT:FormatTimeAgo(timestamp)
    if type(timestamp) ~= "number" then return "\226\128\148" end   -- —
    -- Legacy session-time values are always far below epoch (~10^9). The
    -- migration in LootHistory:Initialize nils these on first load, but we
    -- guard here too in case a stale entry slips through.
    if timestamp < 1e9 then return "\226\128\148" end

    local diff = time() - timestamp
    if diff < 0 then return "\226\128\148" end
    if diff < 60       then return string.format("%ds ago",  diff) end
    if diff < 3600     then return string.format("%dm ago",  math.floor(diff / 60)) end
    if diff < 86400    then return string.format("%dh ago",  math.floor(diff / 3600)) end
    if diff < 86400*7  then return string.format("%dd ago",  math.floor(diff / 86400)) end
    if diff < 86400*30 then return string.format("%dw ago",  math.floor(diff / 86400 / 7)) end
    return string.format("%dmo ago", math.floor(diff / 86400 / 30))
end

--- Convert a Blizzard format string (e.g. LOOT_ITEM) to a Lua pattern.
--- %s → (.+), %d → (%d+), other pattern-special characters are escaped.
function IT:FormatToPattern(fmt)
    -- Strip positional specifiers: %1$s → %s, %2$d → %d (locale reordering)
    fmt = fmt:gsub("%%(%d+)%$([sd])", "%%%2")
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

-- /kit is the new primary alias under the "Klopfer's Item Tracker" rebrand;
-- /it and /itemtracker are kept for muscle memory / backwards compatibility.
SLASH_ITEMTRACKER1 = "/kit"
SLASH_ITEMTRACKER2 = "/it"
SLASH_ITEMTRACKER3 = "/itemtracker"

-- The dispatcher is intentionally lean: anything reachable in the UI lives in
-- the UI. What stays here is what's actually faster as a CLI — diagnostic
-- toggles, version, status, destructive shortcuts, and the test harness.
SlashCmdList["ITEMTRACKER"] = function(msg)
    msg = msg:trim():lower()

    if msg == "" or msg == "gear" or msg == "goals" or msg == "bis" then
        if IT.GearGoalsUI and IT.GearGoalsUI.Toggle then
            IT.GearGoalsUI:Toggle()
        end
    elseif msg == "debug" then
        IT.debugMode = not IT.debugMode
        IT:Print("Debug mode: " .. (IT.debugMode and "ON" or "OFF"), IT.Colors.info)
    elseif msg == "version" then
        IT:Print("Version " .. IT.VERSION .. " (" .. IT.BUILD .. ")", IT.Colors.info)
    elseif msg == "clear" then
        if IT.LootHistory then
            IT.LootHistory:Clear()
        end
        if IT.LootDetector and IT.LootDetector.ResetSessionGold then
            IT.LootDetector:ResetSessionGold()
        end
        if IT.GoldTracker and IT.GoldTracker.Reset then
            IT.GoldTracker:Reset()
        end
        IT:Print("Loot history and session gold cleared.", IT.Colors.success)
    elseif msg == "test" or msg:match("^test ") then
        -- Bare /kit test prints the menu instead of firing a random simulator,
        -- so the user can discover what's testable without guessing.
        local TEST_DISPATCH = {
            loot    = { fn = function() IT:FireTestLoot()           end, desc = "Fake loot drop toast"                  },
            gold    = { fn = function() IT:FireTestGold()           end, desc = "Fake gold drop toast"                  },
            roll    = { fn = function() IT:FireTestRoll()           end, desc = "Fake group roll (Need / Greed / Pass)" },
            council = { fn = function() IT:FireTestLC()             end, desc = "Fake RCLootCouncil session"            },
            reserve = { fn = function() IT:FireTestReserve()        end, desc = "Fake LootReserve roll"                 },
            bisdrop = { fn = function() IT:FireTestGearGoal()       end, desc = "Fake BiS drop popup"                   },
            token   = { fn = function() IT:FireTestGearGoalToken()  end, desc = "Fake tier-token drop with redemption"  },
            loottext= { fn = function() if IT.LootText then IT.LootText:FireTest() end end, desc = "Scrolling loot text burst" },
            conjured= { fn = function() IT:FireTestConjured()      end, desc = "Fake pushed item (healthstone / mage food)" },
        }
        local TEST_ORDER = { "loot", "gold", "roll", "council", "reserve", "bisdrop", "token", "loottext", "conjured" }
        local sub = msg:match("^test%s+(.+)$")
        local entry = sub and TEST_DISPATCH[sub]
        if entry then
            entry.fn()
        else
            if sub then
                IT:Print("Unknown test '" .. sub .. "'. Try /kit test for the list.", IT.Colors.warning)
            else
                IT:Print("Test simulators (UI smoke tests):", IT.Colors.highlight)
                for _, key in ipairs(TEST_ORDER) do
                    IT:Print(string.format("  /kit test %-8s - %s", key, TEST_DISPATCH[key].desc), IT.Colors.info)
                end
            end
        end
    elseif msg:match("^which") then
        -- Diagnostic: explain *why* a given itemID would (or wouldn't) trigger
        -- a GEAR_GOAL_DROPPED popup. Lists every goal on this character that
        -- the dropped item matches — directly, or through token redemption —
        -- with the phase-eligibility flag so a "false positive" notification
        -- can be traced back to the actual offending wishlist entry.
        local arg = msg:match("^which%s+(.+)$")
        local itemID = arg and (tonumber(arg) or tonumber(arg:match("item:(%d+)")))
        local GG = IT.GearGoals
        local Tokens = IT.GearGoalsTokens
        if not itemID then
            IT:Print("Usage: /kit which <itemID or item link>", IT.Colors.warning)
        elseif not (GG and GG.FindAllMatches) then
            IT:Print("GearGoals not initialized.", IT.Colors.warning)
        else
            local name = GetItemInfo(itemID) or ("Item " .. itemID)
            local currentPhase = GG:GetCurrentPhase()
            IT:Print(string.format("Why does %s (id %d) trigger a popup?", name, itemID), IT.Colors.highlight)
            IT:Print("Current phase: " .. currentPhase .. " (notifications fire for current + pre-raid only)", IT.Colors.info)
            local found = false
            local function dump(label, m, goalID)
                found = true
                local goalName = GetItemInfo(goalID) or ("Item " .. goalID)
                local lname = (GG.GetLoadoutName and GG:GetLoadoutName(m.specKey)) or m.specKey
                local plabel = (GG.PHASE_LABEL and GG.PHASE_LABEL[m.phase]) or m.phase
                local eligible = (m.phase == currentPhase) or (m.phase == "pre-raid")
                IT:Print(string.format("  %s %s [%s, %s, rank #%d]  %s",
                    label, goalName, lname, plabel, m.rank or 0,
                    eligible and "(notifies)" or "(suppressed: not current phase)"),
                    IT.Colors.info)
            end
            for _, m in ipairs(GG:FindAllMatches(itemID)) do
                dump("Direct:", m, itemID)
            end
            if Tokens and Tokens:IsToken(itemID) then
                IT:Print("This is a tier-set token — checking redemptions:", IT.Colors.info)
                for _, m in ipairs(GG:FindAllMatchesForToken(itemID)) do
                    dump("Token redeems for:", m, m.goal and m.goal.itemID or 0)
                end
            end
            if not found then
                IT:Print("  No matches on any loadout / phase. Popup would NOT fire.", IT.Colors.success)
            end
        end
    elseif msg:match("^drop") then
        -- Push an item through the real LootDetector → GearGoalsDetector
        -- pipeline so we can confirm whether matching fires for a given ID.
        -- Unlike /kit test bisdrop (which fires a synthetic GEAR_GOAL_DROPPED
        -- with hardcoded matches), this path actually walks goals + token
        -- redemptions, so a popup here means the matching code agrees with
        -- the real-drop case.
        local arg = msg:match("^drop%s+(.+)$")
        local itemID = arg and (tonumber(arg) or tonumber(arg:match("item:(%d+)")))
        if not itemID then
            IT:Print("Usage: /kit drop <itemID or item link>", IT.Colors.warning)
        else
            local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            if not name then
                IT:Print("Item " .. itemID .. " is not cached — open its tooltip in-game first, then retry.", IT.Colors.warning)
            else
                if IT.GearGoals and IT.GearGoals.ClearSeen then
                    IT.GearGoals:ClearSeen(itemID)
                end
                IT:Print("Simulating drop of " .. (link or name) .. " (id " .. itemID .. ")", IT.Colors.info)
                IT.Events:Fire("ITEM_LOOTED", {
                    itemLink    = link or name,
                    itemID      = itemID,
                    quality     = quality or 4,
                    count       = 1,
                    player      = UnitName("player"),
                    isSelf      = true,
                    isGroupLoot = false,
                    timestamp   = time(),
                    icon        = icon,
                })
            end
        end
    elseif msg == "dump" then
        -- Brute-force diagnostic: dump every goal on this character, with
        -- the token each goal item resolves to (if any). Use this when
        -- /kit which says no matches but a popup fired — the offending
        -- entry will show up here even if Tokens:GetTokenFor returns nil
        -- for it (the line will just have an empty token column).
        local GG = IT.GearGoals
        local Tokens = IT.GearGoalsTokens
        if not (GG and IT.charDB and IT.charDB.goals) then
            IT:Print("GearGoals not initialized or no goals stored.", IT.Colors.warning)
        else
            local total = 0
            for loadoutID, byPhase in pairs(IT.charDB.goals) do
                local lname = (GG.GetLoadoutName and GG:GetLoadoutName(loadoutID)) or loadoutID
                IT:Print("Loadout: " .. lname, IT.Colors.highlight)
                for phase, bySlot in pairs(byPhase) do
                    local plabel = (GG.PHASE_LABEL and GG.PHASE_LABEL[phase]) or phase
                    local rows = {}
                    for slotID, goals in pairs(bySlot) do
                        for _, g in ipairs(goals) do
                            total = total + 1
                            local name = (g.itemID and GetItemInfo(g.itemID)) or ("Item " .. tostring(g.itemID))
                            local tokenID = Tokens and Tokens.GetTokenFor and Tokens:GetTokenFor(g.itemID)
                            local tokenStr = tokenID
                                and string.format("  → token %s (%d)",
                                    Tokens:GetSourceTokenLabel(tokenID), tokenID)
                                or ""
                            table.insert(rows, string.format("    [slot %d #%d]  %s (%d)%s",
                                slotID, g.rank or 0, name, g.itemID or 0, tokenStr))
                        end
                    end
                    if #rows > 0 then
                        IT:Print("  Phase " .. plabel .. ":", IT.Colors.info)
                        for _, r in ipairs(rows) do IT:Print(r, IT.Colors.info) end
                    end
                end
            end
            if total == 0 then
                IT:Print("No goals stored on this character.", IT.Colors.info)
            else
                IT:Print(string.format("Total: %d goals across all loadouts.", total), IT.Colors.success)
            end
        end
    elseif msg == "loottext" or msg:match("^loottext ") then
        -- Position the scrolling loot text. Bare command toggles the drag box;
        -- `lock`/`unlock`/`reset` are explicit.
        local sub = msg:match("^loottext%s+(.+)$")
        if not IT.LootText then
            IT:Print("Loot text module not loaded.", IT.Colors.warning)
        elseif sub == "lock" then
            IT.LootText:Lock()
        elseif sub == "unlock" then
            IT.LootText:Unlock()
        elseif sub == "reset" then
            IT.LootText:ResetPosition()
            IT:Print("Loot text position reset to default.", IT.Colors.success)
        else
            IT.LootText:ToggleMover()
        end
    elseif msg == "status" then
        IT:Print("Addon: " .. (IT.db.settings.enabled and "ON" or "OFF"), IT.Colors.info)
        IT:Print("RCLootCouncil: " .. (IT.RCLCIntegration and IT.RCLCIntegration:IsActive() and "active" or "not detected"), IT.Colors.info)
        IT:Print("LootReserve: " .. (IT.LRIntegration and IT.LRIntegration:IsActive() and "active" or "not detected"), IT.Colors.info)
        IT:Print("History: " .. (IT.LootHistory and IT.LootHistory:GetCount() or 0) .. " entries", IT.Colors.info)
        if IT.GoldTracker then
            local r = IT.GoldTracker:GetRates()
            IT:Print("Gold/hr: " .. IT:FormatCopper(math.floor(r.rawPerHour))
                .. "  Vendor/hr: " .. IT:FormatCopper(math.floor(r.vendorPerHour))
                .. (r.hasAuctionator and ("  AH/hr: " .. IT:FormatCopper(math.floor(r.ahPerHour))) or ""),
                IT.Colors.info)
        end
        IT:Print("ElvUI: " .. (IT.ElvUIDataText and IT.ElvUIDataText:IsActive() and "active" or "not detected"), IT.Colors.info)
    else
        IT:Print("Commands (most things are in the UI — open with /kit):", IT.Colors.highlight)
        IT:Print("  /kit              - Toggle gear tracker window", IT.Colors.info)
        IT:Print("  /kit status       - Show integration status", IT.Colors.info)
        IT:Print("  /kit clear        - Clear loot history and session gold", IT.Colors.info)
        IT:Print("  /kit debug        - Toggle debug mode", IT.Colors.info)
        IT:Print("  /kit version      - Show version", IT.Colors.info)
        IT:Print("  /kit test         - List UI smoke-test simulators", IT.Colors.info)
        IT:Print("  /kit loottext     - Move the scrolling loot text (unlock/lock/reset)", IT.Colors.info)
        IT:Print("  /kit which <id>   - Explain why an item would trigger a popup", IT.Colors.info)
        IT:Print("  /kit dump         - Dump every goal on this character (item + resolved token)", IT.Colors.info)
        IT:Print("  /kit drop <id>    - Push an itemID through the real detector pipeline", IT.Colors.info)
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
        timestamp   = time(),
        icon        = item.icon,
    }

    IT:Print("Test loot: " .. fakeLink .. " by " .. player, IT.Colors.info)
    IT.Events:Fire("ITEM_LOOTED", entry)
end

-- Conjured food / healthstones / crafted items arrive as "You receive item:"
-- (pushed) lines, NOT "You receive loot:" — verify that stream end-to-end by
-- feeding a real pushed message through the actual LootDetector parser.
local TEST_PUSHED = {
    { id = 22105, name = "Master Healthstone" },       -- warlock healthstone
    { id = 22895, name = "Conjured Cinnamon Roll" },   -- mage conjured food
}

function IT:FireTestConjured()
    testCounter = testCounter + 1
    local item = TEST_PUSHED[(testCounter - 1) % #TEST_PUSHED + 1]
    local fakeLink = "|cFFFFFFFF|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"
    local fmt = LOOT_ITEM_PUSHED_SELF or "You receive item: %s."
    local msg = fmt:gsub("%%s", fakeLink)
    IT:Print("Test conjured/pushed item: " .. fakeLink, IT.Colors.info)
    if IT.LootDetector then IT.LootDetector:SimulateChatLoot(msg) end
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
    local players = {
        "Thrall", "Jaina", "Sylvanas", "Arthas", "Illidan",
        "Kael", "Vashj", "Maiev", "Tyrande", "Cairne",
        "Vol'jin", "Garrosh", "Rexxar", "Akama", "Medivh",
    }
    local types = { "need", "greed", "pass", "disenchant" }
    for i, p in ipairs(players) do
        C_Timer.After(i * 0.6, function()
            local rollType = types[math.random(1, #types)]
            local num = (rollType ~= "pass") and math.random(1, 100) or 0
            local rollEntry = { player = p, rollType = rollType, number = num }
            table.insert(rollData.rolls, rollEntry)
            IT.Events:Fire("ROLL_UPDATE", rollID, rollEntry)
            IT:Print("  " .. p .. ": " .. rollType .. (num > 0 and (" " .. num) or ""), IT.Colors.info)
        end)
    end

    -- Simulate winner after all rolls
    C_Timer.After(#players * 0.6 + 1.5, function()
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

function IT:FormatCopper(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end
local FormatCopper = function(c) return IT:FormatCopper(c) end

function IT:FireTestGold()
    if IT.LootDetector and IT.LootDetector._addTestGold then
        local copper = math.random(10000, 250000)
        IT.LootDetector._addTestGold(copper)
        local total = IT.LootDetector:GetSessionGold()
        IT:Print("Test gold: +" .. FormatCopper(copper) .. "  (session: " .. FormatCopper(total) .. ")", IT.Colors.highlight)
    end
end

-- Synthetic GEAR_GOAL_DROPPED so the popup can be smoke-tested without
-- needing real goals + a real drop. Bypasses dedup and rank suppression.
function IT:FireTestGearGoal()
    local item = TEST_ITEMS[(testCounter % #TEST_ITEMS) + 1]
    testCounter = testCounter + 1
    local fakeLink = "|cFF" .. string.format("%02X%02X%02X",
        IT.QUALITY_COLORS[item.quality].r * 255,
        IT.QUALITY_COLORS[item.quality].g * 255,
        IT.QUALITY_COLORS[item.quality].b * 255)
        .. "|Hitem:" .. item.id .. "::::::::70:::::|h[" .. item.name .. "]|h|r"

    IT:Print("Test gear-goal drop: " .. fakeLink, IT.Colors.info)
    IT.Events:Fire("GEAR_GOAL_DROPPED", {
        itemID   = item.id,
        itemLink = fakeLink,
        slotID   = INVSLOT_NECK,   -- arbitrary for the test
        looter   = TEST_PLAYERS[(testCounter % #TEST_PLAYERS) + 1],
        fromChat = false,
        matches  = {
            { specKey = "TEST-Main",     phase = "3", slotID = INVSLOT_NECK, rank = 1, isMainSpec = true  },
            { specKey = "TEST-Off",      phase = "3", slotID = INVSLOT_NECK, rank = 2, isMainSpec = false },
        },
    })
end

--- Synthetic token drop: simulates Helm of the Fallen Hero dropping for a
--- Shaman who has *both* a Resto goal (Cyclone Helm, main spec) and an Ele
--- goal (Cataclysm Headpiece, off spec). The popup therefore shows both
--- ROLL 100 (MS) and ROLL 99 (OS) buttons, matching the cross-spec scenario.
function IT:FireTestGearGoalToken()
    local tokenID = 29761   -- Helm of the Fallen Hero
    local fakeLink = "|cFFA335EE|Hitem:" .. tokenID .. "::::::::70:::::|h[Helm of the Fallen Hero]|h|r"

    IT:Print("Test token drop: " .. fakeLink, IT.Colors.info)
    IT.Events:Fire("GEAR_GOAL_DROPPED", {
        itemID   = tokenID,
        itemLink = fakeLink,
        slotID   = INVSLOT_HEAD,
        looter   = "Mograine",
        fromChat = false,
        matches  = {
            { specKey = "SHAMAN-Restoration", phase = "1", slotID = INVSLOT_HEAD,
              rank = 1, isMainSpec = true,  isToken = true, goalItemID = 29028 }, -- Cyclone Helm
            { specKey = "SHAMAN-Elemental",   phase = "1", slotID = INVSLOT_HEAD,
              rank = 1, isMainSpec = false, isToken = true, goalItemID = 28963 }, -- Cataclysm Headpiece
        },
    })
end
