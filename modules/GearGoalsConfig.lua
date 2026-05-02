--[[
    GearGoals settings panel — sub-category of "Klopfer's Item Tracker"
    in the modern Blizzard Settings panel. Laid out as a canvas with
    native widget templates so it visually matches TBCA_BIS and
    Blizzard's own panels.

    Controls:
      - Current Phase: row of buttons (Pre | 1 | 2 | 3 | 3.5 | 4),
        LockHighlight on the active phase. Same pattern as TBCA_BIS.
      - Play sound when a tracked item drops (UICheckButtonTemplate)
      - Open Gear Tracker (UIPanelButtonTemplate)
      - Reset drop popup position (UIPanelButtonTemplate)
]]

local _, IT = ...
local Cfg = {}
IT.GearGoalsConfig = Cfg

-- ============================================================================
-- Phase button labels
-- ============================================================================

local PHASE_LABEL = {
    ["pre-raid"] = "Pre",
    ["1"]        = "1",
    ["2"]        = "2",
    ["3"]        = "3",
    ["3.5"]      = "3.5",
    ["4"]        = "4",
}

local function ButtonWidthFor(label)
    if label == "Pre"  then return 34 end
    if label == "3.5"  then return 32 end
    return 26
end

-- ============================================================================
-- State
-- ============================================================================

local panel
local phaseButtons = {}    -- [phaseString] = button frame
local soundCheck

-- ============================================================================
-- Build
-- ============================================================================

local function BuildPanel()
    if panel then return panel end
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return nil end
    if not (IT.Config and IT.Config.category) then return nil end

    panel = CreateFrame("Frame")
    panel.name = "GearGoals"

    -- Title + subtitle (matches TBCA_BIS / Blizzard panel typography)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GearGoals")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Per-character BiS / loadout tracker — phase, spec, slot.")

    -- Phase selector: label + row of buttons
    local phaseLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    phaseLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -28)
    phaseLabel:SetText("Current Phase:")

    local phases = (IT.GearGoals and IT.GearGoals.PHASES) or {}
    local prev
    for _, phase in ipairs(phases) do
        local label = PHASE_LABEL[phase] or phase
        local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        btn:SetSize(ButtonWidthFor(label), 22)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            btn:SetPoint("LEFT", phaseLabel, "RIGHT", 10, 0)
        end
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            if IT.GearGoals and IT.GearGoals.SetCurrentPhase then
                IT.GearGoals:SetCurrentPhase(phase)
            end
        end)
        phaseButtons[phase] = btn
        prev = btn
    end

    local phaseHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    phaseHint:SetPoint("TOPLEFT", phaseLabel, "BOTTOMLEFT", 0, -8)
    phaseHint:SetText("Goals on this phase (and pre-raid) trigger drop notifications.")

    -- Notify-sound checkbox
    soundCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    soundCheck:SetPoint("TOPLEFT", phaseHint, "BOTTOMLEFT", -4, -16)
    soundCheck.Text:SetText("Play sound when a tracked item drops")
    soundCheck:SetScript("OnClick", function(self)
        IT.db.settings.gearGoals.notifySound = self:GetChecked() and true or false
    end)

    -- Open Gear Tracker button
    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(220, 24)
    openBtn:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 4, -16)
    openBtn:SetText("Open Gear Tracker")
    openBtn:SetScript("OnClick", function()
        if IT.GearGoalsUI and IT.GearGoalsUI.Show then IT.GearGoalsUI:Show() end
    end)

    -- Reset popup position button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(220, 24)
    resetBtn:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -8)
    resetBtn:SetText("Reset drop popup position")
    resetBtn:SetScript("OnClick", function()
        if IT.db and IT.db.settings and IT.db.settings.gearGoals then
            IT.db.settings.gearGoals.popupAnchor = nil
            IT:Print("Drop popup position reset.", IT.Colors.success)
        end
    end)

    -- Repaint controls every time the panel is shown — the legacy
    -- panel.refresh callback is no longer fired by the modern Settings API.
    panel:SetScript("OnShow", function() Cfg:Refresh() end)

    Settings.RegisterCanvasLayoutSubcategory(IT.Config.category, panel, panel.name)
    return panel
end

-- ============================================================================
-- Refresh from saved state
-- ============================================================================

function Cfg:Refresh()
    if not panel or not IT.db then return end

    local s = IT.db.settings.gearGoals
    if soundCheck and s then
        soundCheck:SetChecked(s.notifySound and true or false)
    end

    -- LockHighlight on the current phase button (TBCA_BIS pattern)
    local cur = (IT.GearGoals and IT.GearGoals:GetCurrentPhase()) or "pre-raid"
    for phase, btn in pairs(phaseButtons) do
        if phase == cur then btn:LockHighlight() else btn:UnlockHighlight() end
    end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Cfg:Initialize()
    BuildPanel()
    Cfg:Refresh()
    -- Re-paint when the phase changes from elsewhere (sidebar, slash, etc).
    IT.Events:Subscribe("GEAR_GOALS_PHASE_CHANGED", function() Cfg:Refresh() end)
    IT:Debug("GearGoalsConfig initialized")
end
