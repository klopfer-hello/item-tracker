--[[
    ItemTracker - LDB Data Broker
    Single Responsibility: Expose gold tracking data as a LibDataBroker
    data source so any LDB display (ElvUI, Titan Panel, etc.) can show it.

    Safe: does nothing if LibDataBroker-1.1 is not available.
]]

local _, IT = ...
local LDBDT = {}
IT.ElvUIDataText = LDBDT

-- ============================================================================
-- State
-- ============================================================================

local dataObj    -- LDB data object reference
local registered = false

-- ============================================================================
-- Formatting
-- ============================================================================

local function ShortGold(copper)
    if copper < 100 then
        return string.format("%dc", copper)
    elseif copper < 10000 then
        return string.format("%ds %dc", math.floor(copper / 100), copper % 100)
    else
        local g = math.floor(copper / 10000)
        local s = math.floor((copper % 10000) / 100)
        if s > 0 then
            return string.format("%dg %ds", g, s)
        end
        return string.format("%dg", g)
    end
end

local function FormatDuration(hours)
    local totalMin = math.floor(hours * 60)
    local h = math.floor(totalMin / 60)
    local m = totalMin % 60
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    return string.format("%dm", math.max(m, 1))
end

-- ============================================================================
-- LDB Callbacks
-- ============================================================================

local function OnTooltipShow(tooltip)
    if not IT.GoldTracker then
        tooltip:AddLine("|cFF00D1FFItemTracker|r — No data")
        return
    end

    local r = IT.GoldTracker:GetRates()

    -- Header
    tooltip:AddLine("|cFF00D1FFItemTracker|r — Session Gold")
    tooltip:AddLine(" ")

    -- Session info
    tooltip:AddDoubleLine("Session:", FormatDuration(r.hours), 0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddLine(" ")

    -- Session totals
    tooltip:AddLine("Looted this session", 1, 0.82, 0)
    tooltip:AddDoubleLine("  Raw gold:",
        ShortGold(r.rawCopper),
        0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("  Vendor value:",
        ShortGold(r.vendorCopper),
        0.8, 0.8, 0.8, 1, 1, 1)
    if r.hasAuctionator then
        tooltip:AddDoubleLine("  AH value:",
            ShortGold(r.ahCopper),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    tooltip:AddLine(" ")

    -- Per-hour rates
    tooltip:AddLine("Per Hour", 1, 0.82, 0)
    tooltip:AddDoubleLine("  Raw gold/hr:",
        ShortGold(math.floor(r.rawPerHour)),
        0.8, 0.8, 0.8, 1, 1, 1)
    tooltip:AddDoubleLine("  Vendor/hr:",
        ShortGold(math.floor(r.vendorPerHour)),
        0.8, 0.8, 0.8, 1, 1, 1)
    if r.hasAuctionator then
        tooltip:AddDoubleLine("  AH/hr:",
            ShortGold(math.floor(r.ahPerHour)),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    tooltip:AddLine(" ")

    -- Hints
    tooltip:AddLine("Left-click: Loot history", 0.5, 0.5, 0.5)
    tooltip:AddLine("Shift-click: Settings", 0.5, 0.5, 0.5)
    tooltip:AddLine("Right-click: Reset session", 0.5, 0.5, 0.5)
end

local function OnClick(self, button)
    if button == "LeftButton" then
        if IsShiftKeyDown() then
            if IT.Config then IT.Config:Toggle() end
        else
            if IT.UI then IT.UI:ToggleHistory() end
        end
    elseif button == "RightButton" then
        if IT.GoldTracker then IT.GoldTracker:Reset() end
    end
end

-- ============================================================================
-- Text Update (via event subscription)
-- ============================================================================

local function UpdateText()
    if not dataObj or not IT.GoldTracker then return end

    local r = IT.GoldTracker:GetRates()
    local totalPerHour = r.rawPerHour + r.vendorPerHour
    dataObj.text = ShortGold(math.floor(totalPerHour)) .. "/hr"
end

-- ============================================================================
-- Public API
-- ============================================================================

function LDBDT:IsActive()
    return registered
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function LDBDT:Initialize()
    if not LibStub then return end

    local LDB = LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not LDB then return end

    dataObj = LDB:NewDataObject("ItemTracker Gold", {
        type             = "data source",
        text             = "0g",
        label            = "IT Gold",
        icon             = "Interface\\Icons\\INV_Misc_Coin_01",
        OnTooltipShow    = OnTooltipShow,
        OnClick          = OnClick,
    })

    if not dataObj then return end

    registered = true
    IT:Debug("LDB DataBroker registered")

    -- Update text when rates change
    IT.Events:Subscribe("GOLD_RATES_UPDATED", UpdateText)
end
