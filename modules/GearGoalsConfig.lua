--[[
    ItemTracker - GearGoalsConfig Module
    Single Responsibility: Register a Blizzard Interface Options panel for the
    GearGoals feature so settings live alongside other addons in
    Esc → Interface → AddOns. Mirrors the registration pattern used by
    ItemTracker's own Config module.

    Settings exposed:
      - Open Gear Tracker (button)
      - Current phase (cycle button)
      - Sound on goal drop (checkbox)
      - Reset popup position (button)
]]

local _, IT = ...
local Cfg = {}
IT.GearGoalsConfig = Cfg

-- ============================================================================
-- Palette (matches GearGoalsUI for visual consistency)
-- ============================================================================

local P = {
    label    = { 0.68, 0.68, 0.72 },
    value    = { 0.95, 0.95, 0.97 },
    accent   = { 1.00, 0.78, 0.20 },
    surface  = { 0.10, 0.10, 0.13, 1.0 },
    border   = { 0.22, 0.22, 0.27, 0.95 },
}

local function AddThinBorder(f, c)
    local t  = f:CreateTexture(nil, "OVERLAY"); t:SetPoint("TOPLEFT");     t:SetPoint("TOPRIGHT");     t:SetHeight(1); t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    local bb = f:CreateTexture(nil, "OVERLAY"); bb:SetPoint("BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT"); bb:SetHeight(1); bb:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    local l  = f:CreateTexture(nil, "OVERLAY"); l:SetPoint("TOPLEFT");     l:SetPoint("BOTTOMLEFT");   l:SetWidth(1);  l:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    local rr = f:CreateTexture(nil, "OVERLAY"); rr:SetPoint("TOPRIGHT");   rr:SetPoint("BOTTOMRIGHT"); rr:SetWidth(1); rr:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- ============================================================================
-- Panel state
-- ============================================================================

local panel
local phaseBtn, soundCheck, resetBtn, openBtn

-- ============================================================================
-- Build
-- ============================================================================

local function BuildPanel()
    if panel then return panel end
    if not InterfaceOptions_AddCategory then return nil end

    panel = CreateFrame("Frame")
    panel.name   = "GearGoals"
    panel.parent = "Klopfer's Item Tracker"   -- nest under the parent in the AddOns tree

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFFFFCC33Klopfer's Gear Tracker|r")

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("BiS / loadout tracker per character + spec + phase.")
    sub:SetTextColor(unpack(P.label))

    -- Open Gear Tracker button
    openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(220, 28)
    openBtn:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    openBtn:SetText("Open Gear Tracker")
    openBtn:SetScript("OnClick", function()
        if IT.GearGoalsUI and IT.GearGoalsUI.Show then IT.GearGoalsUI:Show() end
    end)

    -- Current Phase
    local phaseLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    phaseLabel:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -22)
    phaseLabel:SetText("Current phase")
    phaseLabel:SetTextColor(unpack(P.value))

    local phaseHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    phaseHint:SetPoint("TOPLEFT", phaseLabel, "BOTTOMLEFT", 0, -2)
    phaseHint:SetText("Goals on this phase (and pre-raid) trigger drop notifications.")
    phaseHint:SetTextColor(unpack(P.label))

    phaseBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    phaseBtn:SetSize(220, 26)
    phaseBtn:SetPoint("TOPLEFT", phaseHint, "BOTTOMLEFT", 0, -8)
    phaseBtn:SetScript("OnClick", function()
        local GG = IT.GearGoals
        if not GG then return end
        local cur = GG:GetCurrentPhase()
        local idx = 1
        for i, p in ipairs(GG.PHASES) do if p == cur then idx = i; break end end
        local next = GG.PHASES[(idx % #GG.PHASES) + 1]
        GG:SetCurrentPhase(next)
        Cfg:Refresh()
        IT:Print("Current phase set to " .. (GG.PHASE_LABEL[next] or next), IT.Colors.success)
    end)

    -- Notify sound checkbox
    soundCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", phaseBtn, "BOTTOMLEFT", 0, -16)
    soundCheck.Text:SetText("Play sound when a tracked item drops")
    soundCheck.Text:SetTextColor(unpack(P.value))
    soundCheck:SetScript("OnClick", function(self)
        IT.db.settings.gearGoals.notifySound = self:GetChecked() and true or false
    end)

    -- Reset popup position
    resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(220, 26)
    resetBtn:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -16)
    resetBtn:SetText("Reset drop popup position")
    resetBtn:SetScript("OnClick", function()
        IT.db.settings.gearGoals.popupAnchor = nil
        IT:Print("Drop popup position reset.", IT.Colors.success)
    end)

    -- Slash command hints
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -22)
    hint:SetJustifyH("LEFT")
    hint:SetText(table.concat({
        "Slash commands:",
        "  /it gear         — toggle the Gear Tracker window",
        "  /it phase X      — set current phase (pre-raid, 1, 2, 3, 3.5, 4)",
        "  /it test gear    — preview the drop popup",
    }, "\n"))
    hint:SetTextColor(unpack(P.label))

    panel.refresh = function() Cfg:Refresh() end

    InterfaceOptions_AddCategory(panel)
    return panel
end

-- ============================================================================
-- Refresh from saved state
-- ============================================================================

function Cfg:Refresh()
    if not panel or not IT.db then return end
    local s   = IT.db.settings.gearGoals
    local GG  = IT.GearGoals
    if phaseBtn  and GG  then phaseBtn:SetText("Current: " .. (GG.PHASE_LABEL[GG:GetCurrentPhase()] or GG:GetCurrentPhase())) end
    if soundCheck and s   then soundCheck:SetChecked(s.notifySound and true or false) end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Cfg:Initialize()
    BuildPanel()
    Cfg:Refresh()
    -- Re-paint the phase button when the phase is changed elsewhere
    IT.Events:Subscribe("GEAR_GOALS_PHASE_CHANGED", function() Cfg:Refresh() end)
    IT:Debug("GearGoalsConfig initialized")
end
