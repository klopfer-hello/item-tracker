--[[
    ItemTracker - Minimap Module
    Single Responsibility: Render and manage a minimap button
    (draggable around the minimap edge).

    Left-click:  toggle anchor bar + history
    Right-click: open settings
]]

local _, IT = ...
local MM = {}
IT.Minimap = MM

-- ============================================================================
-- Constants
-- ============================================================================

local BUTTON_SIZE   = 31
local MINIMAP_RADIUS = 80   -- approximate minimap radius

-- ============================================================================
-- State
-- ============================================================================

local button  -- the minimap button frame

-- ============================================================================
-- Position Helpers
-- ============================================================================

local function GetButtonPosition(angle)
    local rad = math.rad(angle or 225)
    local x = math.cos(rad) * MINIMAP_RADIUS
    local y = math.sin(rad) * MINIMAP_RADIUS
    return x, y
end

local function UpdatePosition()
    local x, y = GetButtonPosition(IT.db.settings.minimapAngle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- ============================================================================
-- Drag to Reposition Around Minimap
-- ============================================================================

local function OnDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale

    local angle = math.deg(math.atan2(cy - my, cx - mx))
    IT.db.settings.minimapAngle = angle
    UpdatePosition()
end

-- ============================================================================
-- Create Button
-- ============================================================================

local function CreateMinimapButton()
    local f = CreateFrame("Button", "ItemTrackerMinimapButton", Minimap)
    f:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(8)
    f:SetMovable(true)
    f:EnableMouse(true)

    -- Dark circle background (matches LibDBIcon standard)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    -- Icon (positioned to align with standard minimap button layout)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    f.icon = icon

    -- Border (standard minimap button border — must be 53x53 at TOPLEFT)
    local overlay = f:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT", 0, 0)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Highlight
    f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Click handlers
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            if IsShiftKeyDown() then
                if IT.UI then IT.UI:ToggleHistory() end
            else
                if IT.UI then IT.UI:Toggle() end
            end
        elseif btn == "RightButton" then
            if IT.Config then IT.Config:Toggle() end
        end
    end)

    -- Drag to reposition
    f:RegisterForDrag("LeftButton")
    local isDragging = false
    f:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    f:SetScript("OnDragStop", function(self)
        isDragging = false
        self:SetScript("OnUpdate", nil)
        if IT.db and IT.db.settings then
            IT.db.settings.minimapAngle = IT.db.settings.minimapAngle
        end
    end)

    -- Tooltip
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("ItemTracker", 0.28, 0.74, 0.97)
        GameTooltip:AddLine("Left-click: Toggle window", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: Loot history", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Settings", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return f
end

-- ============================================================================
-- Public API
-- ============================================================================

function MM:UpdateVisibility()
    if not button then return end
    if IT.db.settings.showMinimap then
        button:Show()
    else
        button:Hide()
    end
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function MM:Initialize()
    button = CreateMinimapButton()
    UpdatePosition()
    MM:UpdateVisibility()
end
