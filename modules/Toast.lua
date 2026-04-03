--[[
    ItemTracker - Toast Module
    Single Responsibility: Create, animate, and manage pop-up toast
    notifications that appear above the anchor bar.

    Toasts slide up from the anchor bar, stack upward, and fade out
    after a configurable duration. Rolling toasts persist until the
    roll completes.

    Listens to:
        ITEM_LOOTED   — create a loot toast
        ROLL_STARTED  — create a roll toast (persists until roll ends)
        ROLL_UPDATE   — update roll toast with new roll entry
        ROLL_ENDED    — finalize roll toast, start fade timer
]]

local _, IT = ...
local Toast = {}
IT.Toast = Toast

-- ============================================================================
-- Design Constants
-- ============================================================================

local TOAST_WIDTH       = 280
local TOAST_BASE_HEIGHT = 52
local TOAST_ROLL_ROW_H  = 14
local TOAST_PADDING     = 8
local TOAST_ICON_SIZE   = 36
local TOAST_GAP         = 4       -- vertical gap between stacked toasts
local FADE_IN_DURATION  = 0.25
local FADE_OUT_DURATION = 0.5
local SLIDE_DURATION    = 0.2

-- Glassy dark palette
local BG_COLOR    = { 0.06, 0.06, 0.10, 0.82 }
local BORDER_COLOR = { 0.25, 0.70, 0.95, 0.40 }

-- ============================================================================
-- Toast Pool & State
-- ============================================================================

local activeToasts = {}   -- ordered list, [1] = bottom-most toast
local toastPool    = {}   -- recycled frames
local anchorFrame  = nil  -- set by UI module via Toast:SetAnchor()

-- ============================================================================
-- Anchor Management
-- ============================================================================

function Toast:SetAnchor(frame)
    anchorFrame = frame
end

-- ============================================================================
-- Toast Frame Factory
-- ============================================================================

local function CreateToastFrame()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(TOAST_WIDTH, TOAST_BASE_HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(BG_COLOR))
    f:SetBackdropBorderColor(unpack(BORDER_COLOR))

    -- Item icon
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(TOAST_ICON_SIZE, TOAST_ICON_SIZE)
    f.icon:SetPoint("LEFT", f, "LEFT", TOAST_PADDING, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Quality color border around icon
    f.iconBorder = f:CreateTexture(nil, "OVERLAY")
    f.iconBorder:SetSize(TOAST_ICON_SIZE + 2, TOAST_ICON_SIZE + 2)
    f.iconBorder:SetPoint("CENTER", f.icon, "CENTER")
    f.iconBorder:SetColorTexture(1, 1, 1, 0.3)

    -- Item name
    f.itemName = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.itemName:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.itemName:SetPoint("RIGHT", f, "RIGHT", -TOAST_PADDING, 0)
    f.itemName:SetJustifyH("LEFT")
    f.itemName:SetWordWrap(false)

    -- Sub text (player name, count)
    f.subText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.subText:SetPoint("TOPLEFT", f.itemName, "BOTTOMLEFT", 0, -2)
    f.subText:SetPoint("RIGHT", f, "RIGHT", -TOAST_PADDING, 0)
    f.subText:SetJustifyH("LEFT")
    f.subText:SetTextColor(0.70, 0.70, 0.75, 1)

    -- Roll container (font strings added dynamically)
    f.rollLines = {}

    -- Tooltip on hover
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if self.data and self.data.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.data.itemLink)
            GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Fade animation group
    f.fadeIn = f:CreateAnimationGroup()
    local alphaIn = f.fadeIn:CreateAnimation("Alpha")
    alphaIn:SetFromAlpha(0)
    alphaIn:SetToAlpha(1)
    alphaIn:SetDuration(FADE_IN_DURATION)
    f.fadeIn:SetScript("OnPlay", function() f:Show(); f:SetAlpha(0) end)
    f.fadeIn:SetScript("OnFinished", function() f:SetAlpha(1) end)

    f.fadeOut = f:CreateAnimationGroup()
    local alphaOut = f.fadeOut:CreateAnimation("Alpha")
    alphaOut:SetFromAlpha(1)
    alphaOut:SetToAlpha(0)
    alphaOut:SetDuration(FADE_OUT_DURATION)
    f.fadeOut:SetScript("OnFinished", function()
        f:Hide()
        Toast:ReleaseToast(f)
    end)

    f:Hide()
    return f
end

-- ============================================================================
-- Toast Pool Management
-- ============================================================================

local function AcquireToast()
    local f = table.remove(toastPool) or CreateToastFrame()
    f:SetAlpha(1)
    f:Show()
    return f
end

function Toast:ReleaseToast(f)
    f:Hide()
    f:ClearAllPoints()
    f.data = nil
    f.rollID = nil
    f.expireTime = nil
    -- Clear roll lines
    for _, line in ipairs(f.rollLines) do
        line:SetText("")
        line:Hide()
    end
    -- Remove from active list
    for i, t in ipairs(activeToasts) do
        if t == f then
            table.remove(activeToasts, i)
            break
        end
    end
    table.insert(toastPool, f)
    Toast:RepositionAll()
end

-- ============================================================================
-- Layout: stack toasts from anchor (direction configurable)
-- ============================================================================

function Toast:RepositionAll()
    local anchor = anchorFrame or UIParent
    local gap = TOAST_GAP
    local upward = IT.db and IT.db.settings and IT.db.settings.toastUpward ~= false

    for i, toast in ipairs(activeToasts) do
        toast:ClearAllPoints()
        if upward then
            if i == 1 then
                toast:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
            else
                toast:SetPoint("BOTTOMLEFT", activeToasts[i - 1], "TOPLEFT", 0, gap)
            end
        else
            if i == 1 then
                toast:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            else
                toast:SetPoint("TOPLEFT", activeToasts[i - 1], "BOTTOMLEFT", 0, -gap)
            end
        end
    end
end

-- ============================================================================
-- Populate Toast Content
-- ============================================================================

local function SetupToastContent(toast, data)
    toast.data = data

    -- Icon
    if data.icon then
        toast.icon:SetTexture(data.icon)
    else
        toast.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Quality border color
    local r, g, b = IT:GetQualityColor(data.quality or 0)
    toast.iconBorder:SetColorTexture(r, g, b, 0.5)

    -- Item name (colored by quality)
    local hex = IT:GetQualityHex(data.quality or 0)
    local name = data.itemLink and data.itemLink:match("%[(.-)%]") or "Unknown"
    toast.itemName:SetText(hex .. name .. "|r")

    -- Sub text
    local countStr = (data.count and data.count > 1) and (" x" .. data.count) or ""
    if data.isSelf then
        toast.subText:SetText("You" .. countStr)
    else
        toast.subText:SetText((data.player or "Unknown") .. countStr)
    end
end

-- ============================================================================
-- Roll Line Management
-- ============================================================================

local ROLL_TYPE_ICONS = {
    need       = "|cFFFF4444Need|r",
    greed      = "|cFFFFCC00Greed|r",
    disenchant = "|cFF9D4DFFDisenchant|r",
    pass       = "|cFF888888Pass|r",
    council    = "|cFF00D1FFCouncil|r",
    reserve    = "|cFF44FF44Reserve|r",
}

local SOURCE_LABELS = {
    RCLootCouncil = "|cFF00D1FFLoot Council|r",
    LootReserve   = "|cFF44FF44Soft Reserve|r",
}

local function EnsureRollLine(toast, index)
    if not toast.rollLines[index] then
        local line = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetJustifyH("LEFT")
        line:SetTextColor(0.78, 0.78, 0.82, 1)
        toast.rollLines[index] = line
    end
    return toast.rollLines[index]
end

local function UpdateRollDisplay(toast, rolls)
    if not rolls or #rolls == 0 then return end

    local baseY = -TOAST_BASE_HEIGHT + 4
    for i, roll in ipairs(rolls) do
        local line = EnsureRollLine(toast, i)
        local typeStr = ROLL_TYPE_ICONS[roll.rollType] or roll.rollType
        local numStr = (roll.number and roll.number > 0) and (" - " .. roll.number) or ""
        line:SetText("  " .. roll.player .. ": " .. typeStr .. numStr)
        line:SetPoint("TOPLEFT", toast.icon, "BOTTOMLEFT", -TOAST_PADDING + 4,
                      -(i - 1) * TOAST_ROLL_ROW_H)
        line:Show()
    end

    -- Resize toast height
    local rollHeight = #rolls * TOAST_ROLL_ROW_H + 6
    toast:SetHeight(TOAST_BASE_HEIGHT + rollHeight)
    Toast:RepositionAll()
end

-- ============================================================================
-- Public: Create Toasts
-- ============================================================================

function Toast:CreateLootToast(lootEntry)
    -- Enforce max visible toasts
    while #activeToasts >= (IT.db.settings.toastMaxVisible or 5) do
        local oldest = activeToasts[1]
        if oldest then
            oldest.fadeOut:Play()
        else
            break
        end
    end

    local toast = AcquireToast()
    SetupToastContent(toast, lootEntry)
    toast:SetHeight(TOAST_BASE_HEIGHT)

    toast.expireTime = GetTime() + (IT.db.settings.toastDuration or 8)
    table.insert(activeToasts, toast)

    Toast:RepositionAll()
    toast.fadeIn:Play()

    return toast
end

function Toast:CreateRollToast(rollData)
    local toast = AcquireToast()
    SetupToastContent(toast, rollData)
    toast.rollID = rollData.rollID
    toast.expireTime = nil  -- don't auto-expire during roll

    -- Show source-aware status text
    local sourceLabel = rollData.source and SOURCE_LABELS[rollData.source]
    if sourceLabel then
        toast.subText:SetText(sourceLabel .. " |cFFFFCC00in progress...|r")
    else
        toast.subText:SetText("|cFFFFCC00Rolling...|r")
    end

    table.insert(activeToasts, toast)
    Toast:RepositionAll()
    toast.fadeIn:Play()

    return toast
end

-- ============================================================================
-- Find active toast by rollID
-- ============================================================================

local function FindToastByRollID(rollID)
    for _, toast in ipairs(activeToasts) do
        if toast.rollID == rollID then
            return toast
        end
    end
    return nil
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

local function OnItemLooted(lootEntry)
    -- Skip items currently being rolled on (RollTracker handles those)
    if lootEntry.isGroupLoot and IT.RollTracker then
        for _, rollData in pairs(IT.RollTracker:GetActiveRolls()) do
            if rollData.itemID == lootEntry.itemID and not rollData.finished then
                return
            end
        end
    end
    Toast:CreateLootToast(lootEntry)
end

local function OnRollStarted(rollData)
    Toast:CreateRollToast(rollData)
end

local function OnRollUpdate(rollID, rollEntry)
    local toast = FindToastByRollID(rollID)
    if not toast then return end

    local rollData = IT.RollTracker:GetActiveRoll(rollID)
    if rollData then
        UpdateRollDisplay(toast, rollData.rolls)
    end
end

local function OnRollEnded(rollData)
    local toast = FindToastByRollID(rollData.rollID)
    if toast then
        -- Update sub text to show winner
        if rollData.winner then
            toast.subText:SetText("|cFF00FF00Won by: " .. rollData.winner .. "|r")
        else
            toast.subText:SetText("|cFF888888All passed|r")
        end
        -- Start expire timer
        toast.rollID = nil
        toast.expireTime = GetTime() + (IT.db.settings.toastDuration or 8)
    end
end

-- ============================================================================
-- Expiration Timer (OnUpdate)
-- ============================================================================

local timerFrame = CreateFrame("Frame")
local elapsed = 0

timerFrame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0

    local now = GetTime()
    for i = #activeToasts, 1, -1 do
        local toast = activeToasts[i]
        if toast.expireTime and now >= toast.expireTime then
            toast.expireTime = nil
            toast.fadeOut:Play()
        end
    end
end)

-- ============================================================================
-- Module Interface
-- ============================================================================

function Toast:Initialize()
    IT.Events:Subscribe("ITEM_LOOTED", OnItemLooted)
    IT.Events:Subscribe("ROLL_STARTED", OnRollStarted)
    IT.Events:Subscribe("ROLL_UPDATE", OnRollUpdate)
    IT.Events:Subscribe("ROLL_ENDED", OnRollEnded)
end
