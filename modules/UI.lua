--[[
    Klopfer's Item Tracker - UI Module
    Single Responsibility: Render and manage the movable anchor bar that
    serves as the positioning frame for toast notifications.

    The anchor bar is always present:
      - When unlocked it renders as a thin glassy strip you can drag to
        reposition it; toasts stack above (or below, depending on the
        toastUpward setting).
      - When locked it becomes fully transparent (zero visual footprint)
        but still acts as the toast anchor and reveals on hover.

    The legacy stand-alone "Loot History" pop-out window used to live
    here too. It has been retired in favour of the GearGoals window's
    LOOT LOG tab — every entry point that used to open the pop-out
    (anchor-bar click, minimap click, LDB tooltip-area click) now routes
    through IT.GearGoalsUI:OpenLootLog().

    Listens to:
        PLAYER_READY — restore saved bar position
]]

local _, IT = ...
local UI = {}
IT.UI = UI

-- ============================================================================
-- Design Constants
-- ============================================================================

local BAR_WIDTH  = 280
local BAR_HEIGHT = 22

-- Shared dark/gold palette (see modules/Theme.lua).
local P = IT.Theme.P
local SetColor      = IT.Theme.SetColor
local AddBackground = IT.Theme.AddBackground
local AddBorder     = IT.Theme.AddBorder

-- ============================================================================
-- Frames
-- ============================================================================

local barFrame   -- the anchor frame that toasts position relative to

-- ============================================================================
-- Anchor Bar visibility helpers (locked → transparent, unlocked → visible)
-- ============================================================================

local function ShowBar()
    if not barFrame then return end
    barFrame:EnableMouse(true)
    SetColor(barFrame.bg,     P.surface)
    for _, edge in ipairs(barFrame.edges) do
        SetColor(edge, P.borderGold)
    end
    barFrame.title:SetText("|cFFFFCC33Klopfer's Item Tracker|r")
    barFrame.grip:SetText("|cFF666666::::|r")
end

local function HideBar()
    if not barFrame then return end
    SetColor(barFrame.bg, { 0, 0, 0, 0 })
    for _, edge in ipairs(barFrame.edges) do
        SetColor(edge, { 0, 0, 0, 0 })
    end
    barFrame.title:SetText("")
    barFrame.grip:SetText("")
    -- Keep EnableMouse(true) so OnEnter still fires for hover reveal
end

local function UpdateBarVisibility()
    if not barFrame then return end
    if IT.db.settings.locked then
        HideBar()
    else
        ShowBar()
    end
end

-- ============================================================================
-- Anchor Bar
-- ============================================================================

local function CreateAnchorBar()
    local f = CreateFrame("Frame", "ItemTrackerBar", UIParent)
    f:SetSize(BAR_WIDTH, BAR_HEIGHT)
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)

    -- Manual background + border (no BackdropTemplate). Stored on the
    -- frame so ShowBar / HideBar can recolour them as the lock state
    -- toggles between visible (gold border) and fully transparent.
    f.bg    = AddBackground(f, P.surface)
    f.edges = AddBorder(f, P.borderGold)

    -- Title
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.title:SetPoint("LEFT", f, "LEFT", 8, 0)

    -- Grip handle
    f.grip = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.grip:SetPoint("RIGHT", f, "RIGHT", -8, 0)

    -- Dragging
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not IT.db.settings.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        IT.db.settings.position = { point, relativePoint, x, y }
    end)

    -- Click → open the GearGoals LOOT LOG (replaces the old pop-out window).
    f:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            UI:ToggleHistory()
        end
    end)

    -- Tooltip + hover reveal when locked
    f:SetScript("OnEnter", function(self)
        if IT.db.settings.locked then
            ShowBar()
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Klopfer's Item Tracker", P.accent[1], P.accent[2], P.accent[3])
        GameTooltip:AddLine("Left-click: Loot log", 0.7, 0.7, 0.7)
        if not IT.db.settings.locked then
            GameTooltip:AddLine("Drag: Move", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if IT.db.settings.locked then
            HideBar()
        end
    end)

    return f
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Open the unified loot log (GearGoals window's LOOT LOG tab). Closes if
--- the gear window is already open on that tab. Kept on the IT.UI namespace
--- as Toggle / ToggleHistory for backwards compatibility with existing
--- callers (minimap, anchor bar, LDB DataText click).
function UI:ToggleHistory()
    local GUI = IT.GearGoalsUI
    if not GUI then return end
    if GUI:IsShown() and GUI:GetActiveTab() == "LOOT LOG" then
        GUI:Hide()
    else
        GUI:OpenLootLog()
    end
end

function UI:Toggle() UI:ToggleHistory() end

function UI:Show()       if barFrame then barFrame:Show() end end
function UI:Hide()       if barFrame then barFrame:Hide() end end
function UI:IsShown()    return barFrame and barFrame:IsShown() end
function UI:GetAnchorFrame() return barFrame end

-- ============================================================================
-- Position Restore & Lock State
-- ============================================================================

local function RestorePosition()
    local pos = IT.db.settings.position
    if pos then
        barFrame:ClearAllPoints()
        barFrame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end
    UpdateBarVisibility()
end

--- Called by Config when the lock setting changes.
function UI:UpdateLockState()
    UpdateBarVisibility()
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function UI:Initialize()
    barFrame = CreateAnchorBar()

    -- Give Toast module the anchor reference
    if IT.Toast then
        IT.Toast:SetAnchor(barFrame)
    end

    IT.Events:Subscribe("PLAYER_READY", RestorePosition)
end
