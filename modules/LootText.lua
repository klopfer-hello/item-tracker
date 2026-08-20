--[[
    Klopfer's Item Tracker - LootText Module
    Single Responsibility: Show EVERYTHING the player loots (and money) as
    scrolling text on screen, with its own quality filter — completely
    independent of the loot-history quality threshold used for DB tracking.

    Data sources (from LootDetector):
        ITEM_VALUE   — fired for *every* self-looted item, regardless of the
                       history quality threshold. This is the "show it all"
                       stream; ITEM_LOOTED is the threshold-gated stream that
                       feeds the history table, and we intentionally do NOT
                       use it here.
        GOLD_LOOTED  — cumulative session copper; we display the per-drop delta.

    Self-contained scroll engine: TBC Anniversary 2.5.6 removed Blizzard's
    legacy Floating Combat Text engine (CombatText_AddMessage,
    COMBAT_TEXT_TO_ANIMATE, CombatText_GetAvailableString are all gone), so
    this module renders and animates its own pooled FontStrings and does not
    touch the Blizzard combat-text system at all.
]]

local _, IT = ...
local LootText = {}
IT.LootText = LootText

local P = IT.Theme.P

-- ============================================================================
-- Design constants
-- ============================================================================

local BASE_FONT_SIZE = 18
local FONT_FILE      = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local TRAVEL         = 90        -- pixels a line drifts over its lifetime
local FADE_START     = 0.6       -- fraction of lifetime before fade begins
-- Trim the 5..59 texel window so item icons don't show their built-in border.
local ICON_MARKUP    = "|T%s:%d:%d:0:0:64:64:5:59:5:59|t"

-- Blizzard coin icon fileIDs (gold / silver / copper)
local COIN_GOLD   = 133784
local COIN_SILVER = 133786
local COIN_COPPER = 133788

-- ============================================================================
-- State
-- ============================================================================

local anchor, mover, driver
local pool   = {}   -- recycled line frames
local active = {}   -- currently animating lines
local lastGold = 0  -- baseline for GOLD_LOOTED delta

local function S() return IT.db.settings end
local function scaledSize() return math.floor(BASE_FONT_SIZE * (S().lootTextScale or 1) + 0.5) end

-- ============================================================================
-- Line pool + animation
-- ============================================================================

local function acquireLine()
    local line = table.remove(pool)
    if not line then
        line = CreateFrame("Frame", nil, UIParent)
        line:SetFrameStrata("HIGH")
        line:SetSize(1, 1)
        line.fs = line:CreateFontString(nil, "OVERLAY")
        line.fs:SetPoint("CENTER")
    end
    return line
end

local function releaseLine(line)
    line:Hide()
    line.fs:SetText("")
    line.born = nil
    line.startD = nil
    for i = #active, 1, -1 do
        if active[i] == line then table.remove(active, i) break end
    end
    table.insert(pool, line)
    if #active == 0 and driver then driver:Hide() end
end

--- Distance a line currently sits from the anchor (>= 0, along the drift axis).
local function currentDistance(line, now, dur)
    return line.startD + TRAVEL * ((now - line.born) / dur)
end

--- Push a finished text string onto the screen at the anchor and start its rise.
--- Multiple items looted in the same instant (auto-loot) would otherwise all
--- spawn at distance 0 and rise in lockstep, overlapping. We stack each new
--- line at the lowest offset that clears every line still near the anchor;
--- since all lines drift at the same speed, that gap is preserved for life.
local function spawn(text, r, g, b)
    if not anchor then return end
    local now   = GetTime()
    local dur   = S().lootTextDuration or 3
    local lineH = scaledSize() + 6

    local ds = {}
    for _, l in ipairs(active) do ds[#ds + 1] = currentDistance(l, now, dur) end
    table.sort(ds)
    local startD = 0
    for _, d in ipairs(ds) do
        if d >= startD + lineH then
            break               -- clear gap above the candidate slot
        elseif d >= startD then
            startD = d + lineH  -- occupied — stack above this line
        end
    end

    local line = acquireLine()
    -- "OUTLINE" (not "NONE") — 2.5.6's SetFont rejects invalid flag tokens.
    line.fs:SetFont(FONT_FILE, scaledSize(), "OUTLINE")
    line.fs:SetText(text)
    line.fs:SetTextColor(r or 1, g or 1, b or 1)
    line.born   = now
    line.startD = startD
    line.up     = S().lootTextUp ~= false
    line:SetAlpha(1)
    line:ClearAllPoints()
    line:SetPoint("CENTER", anchor, "CENTER", 0, (line.up and 1 or -1) * startD)
    line:Show()
    table.insert(active, line)
    if driver then driver:Show() end
end

-- ============================================================================
-- Message builders
-- ============================================================================

local function displayItem(entry)
    local size    = scaledSize()
    local iconStr = entry.icon and ICON_MARKUP:format(entry.icon, size, size) or ""
    local name    = (entry.itemLink and entry.itemLink:match("%[(.-)%]")) or "Unknown"
    local countStr = (entry.count and entry.count > 1) and (entry.count .. " x ") or ""
    local r, g, b = IT:GetQualityColor(entry.quality or 0)
    spawn(iconStr .. "  " .. countStr .. name, r, g, b)
end

local function displayMoney(copper)
    local size = scaledSize()
    local coin = (copper >= 10000 and COIN_GOLD)
              or (copper >= 100 and COIN_SILVER)
              or COIN_COPPER
    spawn(ICON_MARKUP:format(coin, size, size) .. "  " .. IT:FormatCopper(copper), 1.0, 0.82, 0.0)
end

-- ============================================================================
-- Event handlers
-- ============================================================================

-- ITEM_VALUE fires for every self-looted item regardless of the history
-- threshold — exactly what we want for "show everything I loot".
local function OnItemValue(entry)
    local s = S()
    if not s.lootTextEnable or not s.lootTextShowItems then return end
    if (entry.quality or 0) < (s.lootTextQuality or 0) then return end
    displayItem(entry)
end

-- GOLD_LOOTED carries the cumulative session total; we show the delta so a
-- single pickup scrolls as "+3g 20s". Baseline is always advanced (even when
-- disabled) so toggling the feature on never dumps a giant back-log delta.
local function OnGoldLooted(sessionCopper)
    local delta = (sessionCopper or 0) - lastGold
    lastGold = sessionCopper or 0
    if delta <= 0 then return end          -- reset (/kit clear) or no gain
    local s = S()
    if not s.lootTextEnable or not s.lootTextShowMoney then return end
    displayMoney(delta)
end

-- ============================================================================
-- Anchor + mover (drag-to-position)
-- ============================================================================

local function defaultPos() return { x = 0, y = -80 } end

local function applyPos(x, y)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if mover then
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

local function createFrames()
    anchor = CreateFrame("Frame", "ItemTrackerLootTextAnchor", UIParent)
    anchor:SetSize(200, 20)

    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(230, 34)
    mover:SetFrameStrata("FULLSCREEN_DIALOG")
    IT.Theme.AddBackground(mover, P.surface)
    IT.Theme.AddBorder(mover, P.borderGold)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetText("Loot Text — drag, then /kit loottext")
    mover:EnableMouse(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Derive offset from UIParent centre so it round-trips through a
        -- CENTER anchor regardless of how StartMoving re-anchored the frame.
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        local x, y = (cx - px), (cy - py)
        S().lootTextPos = { x = x, y = y }
        applyPos(x, y)
    end)
    mover:Hide()

    local pos = S().lootTextPos or defaultPos()
    applyPos(pos.x, pos.y)

    -- Animation driver: only runs while lines are on screen.
    driver = CreateFrame("Frame")
    driver:Hide()
    driver:SetScript("OnUpdate", function()
        local now = GetTime()
        local dur = S().lootTextDuration or 3
        for i = #active, 1, -1 do
            local line = active[i]
            local t = (now - line.born) / dur
            if t >= 1 then
                releaseLine(line)
            else
                local y = (line.up and 1 or -1) * (line.startD + TRAVEL * t)
                line:SetPoint("CENTER", anchor, "CENTER", 0, y)
                line:SetAlpha(t < FADE_START and 1 or (1 - (t - FADE_START) / (1 - FADE_START)))
            end
        end
    end)
end

-- ============================================================================
-- Public API
-- ============================================================================

function LootText:IsUnlocked() return mover and mover:IsShown() end

function LootText:Unlock()
    if not mover then return end
    mover:Show()
    IT:Print("Loot text unlocked — drag the box, then |cFFFFD700/kit loottext lock|r.", IT.Colors.info)
    self:FireTest()
end

function LootText:Lock()
    if not mover then return end
    mover:Hide()
    IT:Print("Loot text position locked.", IT.Colors.success)
end

function LootText:ToggleMover()
    if self:IsUnlocked() then self:Lock() else self:Unlock() end
end

function LootText:ResetPosition()
    local p = defaultPos()
    S().lootTextPos = nil
    applyPos(p.x, p.y)
end

-- Preview burst (used by /kit test loottext and on unlock). Bypasses the
-- enable/quality gates so it always shows — it's an explicit user action.
function LootText:FireTest()
    local samples = {
        { name = "Netherweave Cloth", quality = 1, count = 3, icon = 132889 },
        { name = "Adamantite Ore",    quality = 1, count = 2, icon = 134573 },
        { name = "Primal Fire",       quality = 2, count = 1, icon = 135817 },
        { name = "Void Crystal",      quality = 4, count = 1, icon = 134132 },
    }
    for i, it in ipairs(samples) do
        C_Timer.After((i - 1) * 0.4, function()
            displayItem({ itemLink = "[" .. it.name .. "]", quality = it.quality, count = it.count, icon = it.icon })
        end)
    end
    C_Timer.After(#samples * 0.4, function() displayMoney(12345) end)
end

-- ============================================================================
-- Module interface
-- ============================================================================

function LootText:Initialize()
    createFrames()
    IT.Events:Subscribe("ITEM_VALUE", OnItemValue)
    IT.Events:Subscribe("GOLD_LOOTED", OnGoldLooted)
end
