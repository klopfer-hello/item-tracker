--[[
    ItemTracker - GearGoalsCharButton Module
    Single Responsibility: Attach a small "K" button to the Blizzard
    Character paper-doll so the gear-goal window is one click away from
    the player's gear inspection workflow.

    Anchored to PaperDollFrame's bottom-right corner so it shows only on
    the Character tab and stays out of the way of slot icons / model.
    Position is hard-coded; if it collides with another addon's button
    on a different layout, ResetPosition() can be wired up later.
]]

local _, IT = ...
local CB = {}
IT.GearGoalsCharButton = CB

local BUTTON_SIZE = 22

-- Match the GearGoals palette so the button reads as part of the same suite
local P = {
    bg     = { 0.10, 0.10, 0.13, 1.0 },
    bgHi   = { 0.18, 0.14, 0.05, 1.0 },
    border = { 0.62, 0.48, 0.20, 0.95 },
    accent = { 1.00, 0.78, 0.20 },
    label  = { 0.68, 0.68, 0.72 },
}

local function SetColor(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

local function AddBackground(parent, color)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, color)
    return bg
end

local function AddBorder(parent, c)
    for _, p in ipairs({
        { "TOPLEFT",    "TOPRIGHT",    nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT",    "BOTTOMLEFT",  1,   nil },
        { "TOPRIGHT",   "BOTTOMRIGHT", 1,   nil },
    }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetWidth(p[3])  end
        if p[4] then t:SetHeight(p[4]) end
        SetColor(t, c)
    end
end

local button

local function CreateButton()
    if button then return button end

    -- PaperDollFrame is created by Blizzard's CharacterFrame.lua; if it
    -- somehow doesn't exist, fall back to CharacterFrame.
    local parent = _G.PaperDollFrame or _G.CharacterFrame
    if not parent then return nil end

    button = CreateFrame("Button", "ItemTrackerGearGoalsCharButton", parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    -- Bottom-right of the paper-doll, slightly inset so it doesn't sit on
    -- the frame's outer border. Avoids the bottom-edge tab strip.
    button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 32)
    button:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)

    button.bg = AddBackground(button, P.bg)
    AddBorder(button, P.border)

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER", 0, 1)
    button.label:SetText("K")
    button.label:SetTextColor(unpack(P.accent))

    button:SetScript("OnEnter", function(self)
        SetColor(self.bg, P.bgHi)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("|cFFFFCC33Klopfer's Gear Tracker|r")
        GameTooltip:AddLine("Click to open the gear-goal window.", 1, 1, 1)
        GameTooltip:AddLine("Right-click for current-phase setting.", 0.6, 0.6, 0.65)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        SetColor(self.bg, P.bg)
        GameTooltip:Hide()
    end)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            -- Quick-access: cycle the current phase
            if IT.GearGoals then
                local cur = IT.GearGoals:GetCurrentPhase()
                local idx = 1
                for i, p in ipairs(IT.GearGoals.PHASES) do
                    if p == cur then idx = i; break end
                end
                local nextPhase = IT.GearGoals.PHASES[(idx % #IT.GearGoals.PHASES) + 1]
                IT.GearGoals:SetCurrentPhase(nextPhase)
                IT:Print("Current phase: " .. (IT.GearGoals.PHASE_LABEL[nextPhase] or nextPhase),
                    IT.Colors.success)
            end
        else
            -- Character-pane shortcut: always snap to current phase when
            -- opening, since the natural intent is "what am I after right now".
            -- The /it gear slash command still uses the remember-last-view flow.
            if IT.GearGoalsUI and IT.GearGoalsUI.ToggleAtCurrentPhase then
                IT.GearGoalsUI:ToggleAtCurrentPhase()
            elseif IT.GearGoalsUI and IT.GearGoalsUI.Toggle then
                IT.GearGoalsUI:Toggle()
            end
        end
    end)

    return button
end

function CB:Initialize()
    -- The Blizzard CharacterFrame is loaded via the FrameXML on demand on
    -- some flavours. If PaperDollFrame doesn't exist at addon-load, defer
    -- creation until PLAYER_ENTERING_WORLD.
    if _G.PaperDollFrame then
        CreateButton()
    else
        IT:RegisterEvent("PLAYER_ENTERING_WORLD", function()
            if not button then CreateButton() end
        end)
    end
    IT:Debug("GearGoalsCharButton initialized")
end
