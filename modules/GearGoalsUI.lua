--[[
    ItemTracker - GearGoalsUI Module
    Single Responsibility: Main GearGoals window — phase tab bar, slot grid
    with ranked picks, search filter, basic sidebar (slots filled / targets),
    and the add / remove goal interaction.

    Visual style: dark surfaces with gold accents and quality-coloured item
    names — distinct from ItemTracker's cyan/glassy theme.

    Out of scope for MVP (deferred): RAIDS / LOOT LOG tabs, full sidebar
    breakdown, phase actions (Copy / Import / Export), light theme, polished
    typography.
]]

local _, IT = ...
local UI = {}
IT.GearGoalsUI = UI

-- ============================================================================
-- Design palette (mirror of GearGoalsAlert; kept local so each module is
-- self-contained)
-- ============================================================================

local P = {
    bg          = { 0.04, 0.04, 0.06, 1.00 },     -- main backdrop (opaque)
    surface     = { 0.08, 0.08, 0.11, 1.00 },     -- panels
    surfaceAlt  = { 0.12, 0.12, 0.15, 1.00 },     -- alt rows / pills
    border      = { 0.22, 0.22, 0.27, 0.95 },
    borderGold  = { 0.62, 0.48, 0.20, 0.95 },
    accent      = { 1.00, 0.78, 0.20 },           -- gold
    accentDim   = { 0.55, 0.43, 0.18 },
    label       = { 0.68, 0.68, 0.72 },           -- muted but legible
    value       = { 0.95, 0.95, 0.97 },           -- near-white
    success     = { 0.40, 0.85, 0.50 },           -- OWNED
    target      = { 0.95, 0.45, 0.55 },           -- TARGET
    equipped    = { 1.00, 0.70, 0.25 },           -- EQUIPPED
    locked      = { 0.60, 0.32, 0.32 },           -- LOCKED (future phase)
}

local W              = 760
local H              = 620
local SIDEBAR_W      = 200
local TAB_H          = 32
local PHASE_TAB_H    = 44
local HEADER_H       = 48
local FILTER_H       = 36
local SLOT_HEADER_H  = 26
local PICK_ROW_H     = 44

-- ============================================================================
-- State
-- ============================================================================

local frame
local sidebar, content, scrollChild, scrollFrame
local phaseTabs        = {}    -- phase -> button
local slotCards        = {}    -- slotID -> { card, rows{} }
local searchBox
local filterMode       = "ALL"   -- "ALL" or "TARGETS"
local addDialog                  -- inline add-item dialog frame
local searchTerm       = ""
local viewLoadoutID              -- loadout the UI is currently viewing (defaults to main)
local renameDialog               -- inline rename-loadout dialog

-- ============================================================================
-- Helpers
-- ============================================================================

local function SetColor(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

local function AddBackground(parent, color)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, color)
    return bg
end

local function AddBorder(parent, c, thickness)
    thickness = thickness or 1
    for _, p in ipairs({
        { "TOPLEFT",    "TOPRIGHT",    nil, thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness },
        { "TOPLEFT",    "BOTTOMLEFT",  thickness, nil },
        { "TOPRIGHT",   "BOTTOMRIGHT", thickness, nil },
    }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetWidth(p[3])  end
        if p[4] then t:SetHeight(p[4]) end
        SetColor(t, c)
    end
end

local function CreatePanel(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, color or P.surface)
    return f
end

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- Display name for a loadout id, falling back to the id if the loadout
--- is missing.
local function LoadoutLabel(loadoutID)
    if not loadoutID then return "—" end
    local GG = IT.GearGoals
    return (GG and GG.GetLoadoutName) and GG:GetLoadoutName(loadoutID) or loadoutID
end

-- ============================================================================
-- Status pill (small coloured chip)
-- ============================================================================

local function MakeStatusPill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetSize(82, 18)
    local bg = pill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    pill.bg = bg
    AddBorder(pill, P.border)
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pill.text:SetPoint("CENTER")
    return pill
end

local STATUS_STYLE = {
    EQUIPPED = { fill = { 0.32, 0.20, 0.05, 1 }, fg = { 1.00, 0.65, 0.20 } },
    OWNED    = { fill = { 0.10, 0.22, 0.12, 1 }, fg = { 0.30, 0.78, 0.42 } },
    TARGET   = { fill = { 0.28, 0.10, 0.14, 1 }, fg = { 0.92, 0.40, 0.50 } },
    LOCKED   = { fill = { 0.18, 0.10, 0.10, 1 }, fg = { 0.55, 0.30, 0.30 } },
    COVERED  = { fill = { 0.14, 0.14, 0.16, 1 }, fg = { 0.55, 0.55, 0.60 } },
}

local function SetStatus(pill, status)
    local style = STATUS_STYLE[status] or STATUS_STYLE.TARGET
    SetColor(pill.bg, style.fill)
    pill.text:SetText(status)
    pill.text:SetTextColor(style.fg[1], style.fg[2], style.fg[3])
end

-- ============================================================================
-- Header
-- ============================================================================

local function BuildHeader(parent)
    local h = CreatePanel(parent, P.surface)
    h:SetHeight(HEADER_H)
    h:SetPoint("TOPLEFT",  6, -6)
    h:SetPoint("TOPRIGHT", -6, -6)
    AddBorder(h, P.border)

    -- "K" badge (placeholder — design said omit logo for MVP)
    local badge = CreateFrame("Frame", nil, h)
    badge:SetSize(28, 28)
    badge:SetPoint("LEFT", 8, 0)
    AddBackground(badge, P.accentDim)
    AddBorder(badge, P.borderGold)
    local badgeText = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    badgeText:SetPoint("CENTER")
    badgeText:SetText("K")
    badgeText:SetTextColor(unpack(P.accent))

    -- Title
    h.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.title:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    h.title:SetText("KLOPFER'S GEAR TRACKER")
    h.title:SetTextColor(unpack(P.accent))

    -- Char info on the right (auto-updated)
    h.charInfo = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.charInfo:SetPoint("RIGHT", -42, 0)
    h.charInfo:SetTextColor(unpack(P.value))

    -- Close button
    local close = CreateFrame("Button", nil, h)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -8, 0)
    AddBackground(close, P.surfaceAlt)
    AddBorder(close, P.border)
    local x = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    x:SetPoint("CENTER")
    x:SetText("x")
    x:SetTextColor(unpack(P.label))
    close:SetScript("OnEnter", function() x:SetTextColor(unpack(P.value)) end)
    close:SetScript("OnLeave", function() x:SetTextColor(unpack(P.label)) end)
    close:SetScript("OnClick", function() UI:Hide() end)

    return h
end

-- ============================================================================
-- Phase tab bar
-- ============================================================================

local function MakePhaseTab(parent, phase)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(110, PHASE_TAB_H)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, P.surface)
    b.bg = bg

    AddBorder(b, P.border)
    b.bottomBar = b:CreateTexture(nil, "OVERLAY")
    b.bottomBar:SetPoint("BOTTOMLEFT")
    b.bottomBar:SetPoint("BOTTOMRIGHT")
    b.bottomBar:SetHeight(2)
    SetColor(b.bottomBar, { 0, 0, 0, 0 })

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("TOP", 0, -6)
    b.label:SetText(IT.GearGoals.PHASE_LABEL[phase] or phase)

    -- Subtitle is anchored on BOTH sides so the FontString is constrained to
    -- the tab's width — without this, long subtitles bleed past the tab edge
    -- and run into the next tab's text. SetWordWrap(false) clips overflow.
    b.subtitle = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.subtitle:SetPoint("BOTTOMLEFT",  4, 6)
    b.subtitle:SetPoint("BOTTOMRIGHT", -4, 6)
    b.subtitle:SetJustifyH("CENTER")
    b.subtitle:SetWordWrap(false)
    b.subtitle:SetText(IT.GearGoals.PHASE_SUBTITLE[phase] or "")
    b.subtitle:SetTextColor(unpack(P.label))

    b:SetScript("OnClick", function() UI:SetActivePhase(phase) end)
    return b
end

local function BuildPhaseBar(parent, anchorTo)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(PHASE_TAB_H + 6)
    bar:SetPoint("TOPLEFT",  anchorTo, "BOTTOMLEFT",  0, -4)
    bar:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -4)

    local x = 0
    for _, phase in ipairs(IT.GearGoals.PHASES) do
        local t = MakePhaseTab(bar, phase)
        t:SetPoint("TOPLEFT", x, 0)
        x = x + t:GetWidth() + 4
        phaseTabs[phase] = t
    end
    return bar
end

local function PaintPhaseTabs(activePhase, currentPhase)
    for phase, t in pairs(phaseTabs) do
        if phase == activePhase then
            SetColor(t.bg, P.accentDim)
            SetColor(t.bottomBar, P.accent)
            t.label:SetTextColor(unpack(P.accent))
        else
            SetColor(t.bg, P.surface)
            SetColor(t.bottomBar, { 0, 0, 0, 0 })
            t.label:SetTextColor(unpack(P.value))
        end
        -- Mark the *current* (notification) phase with a small gold dot in
        -- the top-right corner; distinct from the *active* (viewed) tab.
        if not t.currentDot then
            t.currentDot = t:CreateTexture(nil, "OVERLAY")
            t.currentDot:SetSize(6, 6)
            t.currentDot:SetPoint("TOPRIGHT", -6, -4)
            SetColor(t.currentDot, P.accent)
        end
        t.currentDot:SetShown(phase == currentPhase)
    end
end

-- ============================================================================
-- Sidebar (slim MVP version)
-- ============================================================================

local function BuildSidebar(parent, anchorTo)
    local s = CreatePanel(parent, P.surface)
    s:SetWidth(SIDEBAR_W)
    s:SetPoint("TOPLEFT",     anchorTo, "BOTTOMLEFT", 0, -8)
    s:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",   6, 6)
    AddBorder(s, P.border)

    s.phaseLabel = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.phaseLabel:SetPoint("TOPLEFT", 14, -14)
    s.phaseLabel:SetText("PHASE")
    s.phaseLabel:SetTextColor(unpack(P.label))

    s.phaseValue = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.phaseValue:SetPoint("TOPLEFT", 14, -28)
    s.phaseValue:SetTextColor(unpack(P.accent))

    s.phaseSub = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.phaseSub:SetPoint("TOPLEFT", 14, -50)
    s.phaseSub:SetTextColor(unpack(P.value))

    -- Stats block
    s.statSlots = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.statSlots:SetPoint("TOPLEFT", 14, -86)
    s.statSlots:SetTextColor(unpack(P.label))
    s.statSlotsValue = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.statSlotsValue:SetPoint("TOPLEFT", 14, -100)
    s.statSlotsValue:SetTextColor(unpack(P.accent))

    s.statTargets = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.statTargets:SetPoint("TOPLEFT", 14, -134)
    s.statTargets:SetText("TARGETS")
    s.statTargets:SetTextColor(unpack(P.label))
    s.statTargetsValue = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    s.statTargetsValue:SetPoint("TOPLEFT", 14, -148)
    s.statTargetsValue:SetTextColor(unpack(P.target))

    s.statSlots:SetText("SLOTS WITH PICKS")

    -- Loadout panel — replaces the old class-based spec selector.
    -- Layout (top to bottom): label, name button (cycles), small action row.
    s.loadoutLabel = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.loadoutLabel:SetPoint("TOPLEFT", 14, -190)
    s.loadoutLabel:SetText("LOADOUT")
    s.loadoutLabel:SetTextColor(unpack(P.label))

    s.loadoutBtn = CreateFrame("Button", nil, s)
    s.loadoutBtn:SetPoint("TOPLEFT", 14, -208)
    s.loadoutBtn:SetSize(SIDEBAR_W - 28, 26)
    s.loadoutBtn.bg = AddBackground(s.loadoutBtn, P.surfaceAlt)
    AddBorder(s.loadoutBtn, P.border)
    s.loadoutBtn.text = s.loadoutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.loadoutBtn.text:SetPoint("LEFT", 8, 0)
    s.loadoutBtn.text:SetTextColor(unpack(P.value))
    s.loadoutBtn:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
    s.loadoutBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.loadoutBtn:SetScript("OnClick", function() UI:CycleLoadout() end)

    -- Action row: rename / set-main / add-second.
    -- These three buttons share the same y position and toggle visibility
    -- in Refresh based on loadout count + main flag.
    local function MakeAction(label, onClick)
        local b = CreateFrame("Button", nil, s)
        b:SetSize((SIDEBAR_W - 28 - 4) / 2, 22)
        b.bg = AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetTextColor(unpack(P.value))
        b.text:SetText(label)
        b:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
        b:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
        b:SetScript("OnClick", onClick)
        return b
    end
    s.renameBtn  = MakeAction("Rename",  function() UI:OpenRenameLoadoutDialog() end)
    s.renameBtn:SetPoint("TOPLEFT", 14, -240)

    s.setMainBtn = MakeAction("Set main", function()
        IT.GearGoals:SetMainLoadout(viewLoadoutID)
        UI:Refresh()
    end)
    s.setMainBtn:SetPoint("TOPLEFT", s.renameBtn, "TOPRIGHT", 4, 0)

    s.addLoadoutBtn = MakeAction("+ Add second loadout", function()
        UI:OpenRenameLoadoutDialog(true)   -- true = add mode
    end)
    s.addLoadoutBtn:SetPoint("TOPLEFT", 14, -240)
    s.addLoadoutBtn:SetWidth(SIDEBAR_W - 28)

    -- "Set as current phase" toggle (acts on the currently viewed phase)
    s.currentPhaseLabel = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.currentPhaseLabel:SetPoint("TOPLEFT", 14, -278)
    s.currentPhaseLabel:SetText("CURRENT PHASE")
    s.currentPhaseLabel:SetTextColor(unpack(P.label))

    s.currentPhaseValue = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.currentPhaseValue:SetPoint("TOPLEFT", 14, -294)
    s.currentPhaseValue:SetTextColor(unpack(P.accent))

    s.setCurrentBtn = CreateFrame("Button", nil, s)
    s.setCurrentBtn:SetPoint("TOPLEFT", 14, -318)
    s.setCurrentBtn:SetSize(SIDEBAR_W - 28, 26)
    s.setCurrentBtn.bg = AddBackground(s.setCurrentBtn, P.surfaceAlt)
    AddBorder(s.setCurrentBtn, P.borderGold)
    s.setCurrentBtn.text = s.setCurrentBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.setCurrentBtn.text:SetPoint("CENTER")
    s.setCurrentBtn.text:SetTextColor(unpack(P.accent))
    s.setCurrentBtn:SetScript("OnEnter", function(self) SetColor(self.bg, P.accentDim) end)
    s.setCurrentBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.setCurrentBtn:SetScript("OnClick", function()
        local viewed = IT.GearGoals:GetViewedPhase()
        IT.GearGoals:SetCurrentPhase(viewed)
        IT:Print("Current phase set to " .. (IT.GearGoals.PHASE_LABEL[viewed] or viewed), IT.Colors.success)
        UI:Refresh()
    end)

    -- PHASE ACTIONS group — Copy from <Previous>. Hidden when viewing
    -- pre-raid (no previous phase exists).
    s.phaseActionsLabel = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.phaseActionsLabel:SetPoint("TOPLEFT", 14, -354)
    s.phaseActionsLabel:SetText("PHASE ACTIONS")
    s.phaseActionsLabel:SetTextColor(unpack(P.label))

    s.copyPhaseBtn = CreateFrame("Button", nil, s)
    s.copyPhaseBtn:SetPoint("TOPLEFT", 14, -370)
    s.copyPhaseBtn:SetSize(SIDEBAR_W - 28, 26)
    s.copyPhaseBtn.bg = AddBackground(s.copyPhaseBtn, P.surfaceAlt)
    AddBorder(s.copyPhaseBtn, P.borderGold)
    s.copyPhaseBtn.text = s.copyPhaseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.copyPhaseBtn.text:SetPoint("CENTER")
    s.copyPhaseBtn.text:SetTextColor(unpack(P.accent))
    s.copyPhaseBtn:SetScript("OnEnter", function(self) SetColor(self.bg, P.accentDim) end)
    s.copyPhaseBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.copyPhaseBtn:SetScript("OnClick", function() UI:RequestPhaseCopy() end)

    return s
end

-- ============================================================================
-- Filter row (search + chips)
-- ============================================================================

local function BuildFilterRow(parent)
    local row = CreatePanel(parent, P.surface)
    row:SetHeight(FILTER_H)
    -- Anchors are set by UI:Build after the sidebar exists
    AddBorder(row, P.border)

    -- Search edit box
    searchBox = CreateFrame("EditBox", nil, row)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextColor(unpack(P.value))
    searchBox:SetSize(280, 22)
    searchBox:SetPoint("LEFT", 28, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        searchTerm = (self:GetText() or ""):lower()
        UI:Refresh()
    end)
    -- Placeholder hint
    row.searchHint = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.searchHint:SetPoint("LEFT", searchBox, "LEFT", 0, 0)
    row.searchHint:SetText("Filter loadout...")
    row.searchHint:SetTextColor(unpack(P.label))
    searchBox:HookScript("OnTextChanged", function(self)
        row.searchHint:SetShown(self:GetText() == "")
    end)

    -- Filter chips
    local function Chip(label, mode, anchorOffset)
        local c = CreateFrame("Button", nil, row)
        c:SetSize(96, 22)
        c:SetPoint("RIGHT", anchorOffset, 0)
        local bg = c:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        c.bg = bg
        AddBorder(c, P.border)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        c.text:SetPoint("CENTER")
        c.text:SetText(label)
        c.mode = mode
        c:SetScript("OnClick", function() UI:SetFilter(mode) end)
        return c
    end
    row.chipAll     = Chip("ALL SLOTS",    "ALL",     -118)
    row.chipTargets = Chip("TARGETS ONLY", "TARGETS", -12)

    function row:Repaint()
        for _, c in ipairs({ row.chipAll, row.chipTargets }) do
            if c.mode == filterMode then
                SetColor(c.bg, P.accentDim)
                c.text:SetTextColor(unpack(P.accent))
            else
                SetColor(c.bg, P.surfaceAlt)
                c.text:SetTextColor(unpack(P.value))
            end
        end
    end
    return row
end

-- ============================================================================
-- Slot card + pick row
-- ============================================================================

local function MakePickRow(parent, slotID)
    -- Must be a Button frame so RegisterForClicks / OnClick work — Frame
    -- doesn't support those in TBC 2.5.5, and a silent error there made
    -- newly added picks vanish (the row never made it into card.rows).
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICK_ROW_H)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, P.surfaceAlt)
    row.bg = bg

    local highlight = row:CreateTexture(nil, "BORDER")
    highlight:SetAllPoints()
    SetColor(highlight, { P.equipped[1], P.equipped[2], P.equipped[3], 0.0 })
    row.highlight = highlight

    -- Rank
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rank:SetPoint("LEFT", 8, 0)
    row.rank:SetWidth(28)
    row.rank:SetJustifyH("CENTER")
    row.rank:SetTextColor(unpack(P.label))

    -- Icon
    row.iconHolder = CreateFrame("Frame", nil, row)
    row.iconHolder:SetSize(28, 28)
    row.iconHolder:SetPoint("LEFT", row.rank, "RIGHT", 4, 0)
    AddBorder(row.iconHolder, P.border)
    row.icon = row.iconHolder:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Item name + source
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.iconHolder, "TOPRIGHT", 8, -2)
    row.name:SetJustifyH("LEFT")

    row.source = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.source:SetPoint("BOTTOMLEFT", row.iconHolder, "BOTTOMRIGHT", 8, 2)
    row.source:SetJustifyH("LEFT")
    row.source:SetTextColor(unpack(P.label))

    -- Reorder arrows (stacked, far right). Visibility set in RenderRow.
    local function MakeArrow(label)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(16, 14)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER", 0, 1)
        t:SetText(label)
        t:SetTextColor(unpack(P.label))
        b.text = t
        b:SetScript("OnEnter", function(self)
            if self:IsEnabled() then self.text:SetTextColor(unpack(P.accent)) end
        end)
        b:SetScript("OnLeave", function(self)
            self.text:SetTextColor(unpack(P.label))
        end)
        return b
    end

    -- WoW's default font on TBC Anniversary doesn't cover Unicode arrow
    -- blocks reliably; using +/- as clean ASCII labels: + moves the pick
    -- up (toward higher priority / smaller rank number), - moves it down.
    row.upBtn = MakeArrow("+")
    row.upBtn:SetPoint("TOPRIGHT", -8, -3)
    row.dnBtn = MakeArrow("-")
    row.dnBtn:SetPoint("BOTTOMRIGHT", -8, 3)

    row.upBtn:SetScript("OnClick", function()
        if not row.goal then return end
        local viewed = IT.GearGoals:GetViewedPhase()
        local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
        IT.GearGoals:MoveGoal(spec, viewed, slotID, row.goal.itemID, -1)
        UI:Refresh()
    end)
    row.dnBtn:SetScript("OnClick", function()
        if not row.goal then return end
        local viewed = IT.GearGoals:GetViewedPhase()
        local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
        IT.GearGoals:MoveGoal(spec, viewed, slotID, row.goal.itemID, 1)
        UI:Refresh()
    end)

    -- ilvl
    row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.ilvl:SetPoint("RIGHT", -134, 0)
    row.ilvl:SetTextColor(unpack(P.value))

    -- Status pill (shifted left to make room for the arrow column)
    row.pill = MakeStatusPill(row)
    row.pill:SetPoint("RIGHT", -32, 0)

    -- Tooltip on hover (also serves as a way to inspect the item)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Right-click: remove
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and self.goal then
            local viewed = IT.GearGoals:GetViewedPhase()
            local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
            IT.GearGoals:RemoveGoal(spec, viewed, slotID, self.goal.itemID)
            UI:Refresh()
        end
    end)

    return row
end

local function MakeSlotCard(parent, slotID)
    local card = CreatePanel(parent, P.surface)
    AddBorder(card, P.border)

    local headerBg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerBg:SetPoint("TOPLEFT")
    headerBg:SetPoint("TOPRIGHT")
    headerBg:SetHeight(SLOT_HEADER_H)
    SetColor(headerBg, P.surfaceAlt)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.title:SetPoint("TOPLEFT", 12, -7)
    card.title:SetText(IT.GearGoals:GetSlotLabel(slotID))
    card.title:SetTextColor(unpack(P.value))

    card.count = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.count:SetPoint("RIGHT", -32, 0)
    card.count:SetPoint("TOP", 0, -7)
    card.count:SetTextColor(unpack(P.label))

    card.addBtn = CreateFrame("Button", nil, card)
    card.addBtn:SetSize(20, 20)
    card.addBtn:SetPoint("TOPRIGHT", -8, -4)
    AddBackground(card.addBtn, P.accentDim)
    AddBorder(card.addBtn, P.borderGold)
    local plus = card.addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    plus:SetPoint("CENTER", 0, 1)
    plus:SetText("+")
    plus:SetTextColor(unpack(P.accent))
    card.addBtn:SetScript("OnClick", function() UI:OpenAddDialog(slotID) end)

    card.rows = {}
    return card
end

-- ============================================================================
-- Add-goal dialog (inline)
-- ============================================================================

local SUGGESTION_ROW_H = 22
local SUGGESTION_MAX   = 8

local function BuildAddDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsAddDialog", parent)
    d:SetFrameStrata("DIALOG")
    -- Tall enough to accommodate up to 8 suggestion rows under the editbox.
    d:SetSize(380, 360)
    d:SetPoint("CENTER")
    d:Hide()

    AddBackground(d, P.bg)
    local inner = CreateFrame("Frame", nil, d)
    inner:SetPoint("TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", -6, 6)
    AddBackground(inner, P.surface)
    AddBorder(inner, P.borderGold)

    d.title = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -10)
    d.title:SetTextColor(unpack(P.accent))

    d.label = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.label:SetPoint("TOPLEFT", 16, -40)
    d.label:SetText("Item name or ID")
    d.label:SetTextColor(unpack(P.label))

    d.editBox = CreateFrame("EditBox", nil, inner)
    d.editBox:SetFontObject("GameFontHighlight")
    d.editBox:SetSize(348, 24)
    d.editBox:SetPoint("TOPLEFT", 16, -56)
    d.editBox:SetAutoFocus(true)
    d.editBox:SetScript("OnEscapePressed", function() d:Hide() end)
    d.editBox:SetScript("OnEnterPressed",  function() UI:ConfirmAdd() end)
    AddBackground(d.editBox, P.surfaceAlt)
    AddBorder(d.editBox, P.border)

    -- Suggestion popup directly under the editbox. Fixed slot for up to
    -- SUGGESTION_MAX rows; rows are show/hidden based on the result count.
    d.suggestionsPanel = CreateFrame("Frame", nil, inner)
    d.suggestionsPanel:SetPoint("TOPLEFT",  16, -86)
    d.suggestionsPanel:SetPoint("TOPRIGHT", -16, -86)
    d.suggestionsPanel:SetHeight(SUGGESTION_ROW_H * SUGGESTION_MAX)
    AddBackground(d.suggestionsPanel, P.surfaceAlt)
    AddBorder(d.suggestionsPanel, P.border)
    d.suggestionsPanel:Hide()
    d.suggestionRows = {}

    d.suggestionsEmpty = d.suggestionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.suggestionsEmpty:SetPoint("CENTER")
    d.suggestionsEmpty:SetText("No matches")
    d.suggestionsEmpty:SetTextColor(unpack(P.label))
    d.suggestionsEmpty:Hide()

    d.errorText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Single-anchor + SetWidth so multiline isn't clipped (two-corner anchors
    -- on a FontString in TBC Classic suppress wrapping).
    d.errorText:SetPoint("TOPLEFT", d.suggestionsPanel, "BOTTOMLEFT", 0, -8)
    d.errorText:SetWidth(348)
    d.errorText:SetJustifyH("LEFT")
    d.errorText:SetTextColor(unpack(P.target))

    -- Buttons
    local function MakeBtn(label, anchor, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(110, 24)
        b:SetPoint("BOTTOM" .. anchor, x, 10)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(label)
        t:SetTextColor(unpack(P.value))
        return b
    end
    d.addBtn    = MakeBtn("Add",    "RIGHT", -16)
    d.cancelBtn = MakeBtn("Cancel", "LEFT",   16)

    d.addBtn:SetScript("OnClick",    function() UI:ConfirmAdd() end)
    d.cancelBtn:SetScript("OnClick", function() d:Hide() end)

    -- Live suggestion refresh as the user types, plus an initial pass when
    -- the dialog is shown so the BiS list is visible without typing.
    d.editBox:HookScript("OnTextChanged", function() UI:RefreshAddSuggestions() end)
    d:HookScript("OnShow",                function() UI:RefreshAddSuggestions() end)

    return d
end

--- Construct (or reuse) a single row in the suggestions panel. Each row is
--- a Button so it supports OnClick / RegisterForClicks (Frame can't).
local function BuildSuggestionRow(panel, index)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(SUGGESTION_ROW_H)
    row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  2, -((index - 1) * SUGGESTION_ROW_H + 2))
    row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -((index - 1) * SUGGESTION_ROW_H + 2))

    row.bg = AddBackground(row, { 0, 0, 0, 0 })

    -- Icon
    row.iconHolder = CreateFrame("Frame", nil, row)
    row.iconHolder:SetSize(SUGGESTION_ROW_H - 4, SUGGESTION_ROW_H - 4)
    row.iconHolder:SetPoint("LEFT", 4, 0)
    row.icon = row.iconHolder:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Item name (quality-coloured)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.iconHolder, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -54, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Source tag (BiS / Seen) on the right
    row.sourceTag = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sourceTag:SetPoint("RIGHT", -6, 0)
    row.sourceTag:SetWidth(46)
    row.sourceTag:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        SetColor(self.bg, { P.accent[1], P.accent[2], P.accent[3], 0.18 })
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- Use the abbreviated `item:N` hyperlink form for compatibility
            -- (SetItemByID isn't available in TBC 2.5.5).
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        SetColor(self.bg, { 0, 0, 0, 0 })
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self)
        if not self.itemID then return end
        if not addDialog or not addDialog:IsShown() then return end
        -- Set the editbox to the itemID and confirm — ResolveNameOrID
        -- recognises numeric input so we don't need a special path.
        addDialog.editBox:SetText(tostring(self.itemID))
        UI:ConfirmAdd()
    end)

    return row
end

--- Repopulate the suggestion popup based on the current editbox contents.
function UI:RefreshAddSuggestions()
    if not addDialog or not addDialog:IsShown() then return end

    local query   = addDialog.editBox:GetText() or ""
    local slotID  = addDialog.slotID
    local loadout = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
    local phase   = IT.GearGoals:GetViewedPhase()

    local suggestions = IT.GearGoals:GetAutocompleteSuggestions(
        slotID, phase, loadout, query, SUGGESTION_MAX
    )

    -- Lazy-grow the row pool
    while #addDialog.suggestionRows < SUGGESTION_MAX do
        local idx = #addDialog.suggestionRows + 1
        addDialog.suggestionRows[idx] = BuildSuggestionRow(addDialog.suggestionsPanel, idx)
    end

    if #suggestions == 0 then
        for _, row in ipairs(addDialog.suggestionRows) do row:Hide() end
        if query == "" then
            -- Empty query + no BiS results: hide the panel entirely
            addDialog.suggestionsPanel:Hide()
        else
            addDialog.suggestionsPanel:Show()
            addDialog.suggestionsEmpty:Show()
        end
        return
    end

    addDialog.suggestionsPanel:Show()
    addDialog.suggestionsEmpty:Hide()

    for i, row in ipairs(addDialog.suggestionRows) do
        local s = suggestions[i]
        if s then
            local icon = select(10, GetItemInfo(s.itemID))
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(s.name)
            local r, g, b = IT:GetQualityColor(s.quality or 1)
            row.name:SetTextColor(r, g, b)
            if s.source == "BiS" then
                row.sourceTag:SetText("|cFFFFCC33BiS|r")
            else
                row.sourceTag:SetText("|cFF888892Seen|r")
            end
            row.itemID = s.itemID
            row:Show()
        else
            row:Hide()
        end
    end
end

local pendingResolutions = {}   -- itemID -> {specKey, phase, slotID, goalRef}

-- Resolve "name or id" string to an itemID using the local cache.
-- Returns: itemID, errorMessage. errorMessage describes "pending" vs "not found".
local function ResolveNameOrID(input)
    input = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then return nil, "Empty input" end

    -- Direct numeric
    local n = tonumber(input)
    if n then
        local name = GetItemInfo(n)
        if name then return n end
        -- Trigger the cache fetch and ask user to retry
        GetItemInfo(n)
        return nil, "Item " .. n .. " not in cache yet — try again in a moment."
    end

    -- Hyperlink? Extract the id directly.
    local id = ItemIDFromLink(input)
    if id then return id end

    -- Best-effort name lookup via GetItemInfo (only resolves cached items).
    local name, link = GetItemInfo(input)
    if name and link then return ItemIDFromLink(link) end
    return nil, "Not in client cache — paste the item link or item ID instead."
end

function UI:OpenAddDialog(slotID)
    if not addDialog then addDialog = BuildAddDialog(frame) end
    addDialog.title:SetText("Add to " .. IT.GearGoals:GetSlotLabel(slotID))
    addDialog.editBox:SetText("")
    addDialog.errorText:SetText("")
    addDialog.slotID = slotID
    addDialog:Show()
    addDialog.editBox:SetFocus()
end

function UI:ConfirmAdd()
    if not addDialog or not addDialog:IsShown() then return end
    local input = addDialog.editBox:GetText() or ""
    local id, err = ResolveNameOrID(input)
    if not id then
        addDialog.errorText:SetText(err or "?")
        return
    end

    -- Verify the resolved item is equippable in the slot (or any slot variant)
    local _, validSlots = IT.GearGoals:ResolveSlotForItem(id)
    if validSlots then
        local match = false
        for _, s in ipairs(validSlots) do
            if s == addDialog.slotID then match = true; break end
        end
        if not match then
            addDialog.errorText:SetText("Item not valid for this slot.")
            return
        end
    end

    local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
    local phase  = IT.GearGoals:GetViewedPhase()
    local _, errAdd = IT.GearGoals:AddGoal(spec, phase, addDialog.slotID, id)
    if errAdd then
        addDialog.errorText:SetText(errAdd)
        return
    end
    addDialog:Hide()
    UI:Refresh()
end

-- ============================================================================
-- Render
-- ============================================================================

local function RenderRow(row, slotID, goal)
    local _, link, _, ilvl, _, _, _, _, _, icon = GetItemInfo(goal.itemID)
    local name, _, quality = GetItemInfo(goal.itemID)
    name = name or ("Item " .. goal.itemID)

    row.itemLink = link
    row.goal     = goal
    row.rank:SetText("#" .. goal.rank)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(name)
    if quality then
        local r, g, b = IT:GetQualityColor(quality)
        row.name:SetTextColor(r, g, b)
    else
        row.name:SetTextColor(unpack(P.value))
    end
    row.ilvl:SetText(ilvl or "")

    local sourceLabel = IT.GearGoalsAtlasLoot
        and IT.GearGoalsAtlasLoot:GetSourceLabel(goal.itemID)
    row.source:SetText(sourceLabel or "")

    local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
    local phase  = IT.GearGoals:GetViewedPhase()
    local status = IT.GearGoals:StatusFor(spec, phase, slotID, goal)
    SetStatus(row.pill, status)

    if status == "EQUIPPED" then
        SetColor(row.highlight, { P.equipped[1], P.equipped[2], P.equipped[3], 0.18 })
    else
        SetColor(row.highlight, { 0, 0, 0, 0 })
    end

    -- Reorder arrows: hide ↑ on rank 1, hide ↓ on the last rank
    local listSize = #IT.GearGoals:GetGoals(spec, phase, slotID)
    if row.upBtn then
        row.upBtn:SetShown(goal.rank > 1)
    end
    if row.dnBtn then
        row.dnBtn:SetShown(goal.rank < listSize)
    end
end

local function RowMatchesSearch(goal)
    if searchTerm == "" then return true end
    local name = GetItemInfo(goal.itemID) or ""
    return name:lower():find(searchTerm, 1, true) ~= nil
end

local function CardMatchesFilter(slotID, goals)
    if filterMode == "ALL" then return #goals > 0 or true end   -- show empty cards too
    -- TARGETS: only show slot if at least one goal is TARGET status
    local spec  = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
    local phase = IT.GearGoals:GetViewedPhase()
    for _, g in ipairs(goals) do
        if IT.GearGoals:StatusFor(spec, phase, slotID, g) == "TARGET" then
            return true
        end
    end
    return false
end

function UI:Refresh()
    if not frame or not frame:IsShown() then return end

    local GG    = IT.GearGoals
    local spec  = viewLoadoutID or GG:GetMainLoadoutID()
    local phase = GG:GetViewedPhase()
    local activePhase = GG:GetCurrentPhase()

    PaintPhaseTabs(phase, activePhase)

    -- Sidebar
    sidebar.phaseValue:SetText(GG.PHASE_LABEL[phase] or phase)
    sidebar.phaseSub:SetText(GG.PHASE_SUBTITLE[phase] or "")

    -- Current-phase indicator + "Set as current" button
    sidebar.currentPhaseValue:SetText(GG.PHASE_LABEL[activePhase] or activePhase)
    if phase == activePhase then
        sidebar.setCurrentBtn:Hide()
    else
        sidebar.setCurrentBtn.text:SetText("SET " .. (GG.PHASE_LABEL[phase] or phase) .. " AS CURRENT")
        sidebar.setCurrentBtn:Show()
    end

    -- Phase Actions: Copy from <previous phase>. Hidden when no previous.
    local prevPhase = GG:GetPreviousPhase(phase)
    if prevPhase then
        sidebar.phaseActionsLabel:Show()
        sidebar.copyPhaseBtn.text:SetText("COPY FROM " .. (GG.PHASE_LABEL[prevPhase] or prevPhase))
        sidebar.copyPhaseBtn:Show()
    else
        sidebar.phaseActionsLabel:Hide()
        sidebar.copyPhaseBtn:Hide()
    end

    local slotsWithPicks, totalTargets = 0, 0
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        local goals = GG:GetGoals(spec, phase, slotID)
        if #goals > 0 then slotsWithPicks = slotsWithPicks + 1 end
        for _, g in ipairs(goals) do
            local status = GG:StatusFor(spec, phase, slotID, g)
            if status == "TARGET" then totalTargets = totalTargets + 1 end
        end
    end
    sidebar.statSlotsValue:SetText(slotsWithPicks .. " / " .. #GG.SLOT_ORDER)
    sidebar.statTargetsValue:SetText(tostring(totalTargets))

    -- Loadout panel — show the viewing loadout's name with a gold "(main)"
    -- marker when it's the main loadout. Action-row visibility:
    --   1 loadout  → only "+ Add second" visible
    --   2 loadouts viewing main      → only "Rename" visible
    --   2 loadouts viewing non-main  → "Rename" + "Set main" visible
    local loadouts = GG:GetLoadouts()
    local mainID   = GG:GetMainLoadoutID()
    local viewing  = GG:GetLoadoutByID(spec)
    local label    = LoadoutLabel(spec)
    if spec == mainID then
        label = label .. "  |cFFFFCC33(main)|r"
    end
    sidebar.loadoutBtn.text:SetText(label)

    if #loadouts < 2 then
        sidebar.renameBtn:Hide()
        sidebar.setMainBtn:Hide()
        sidebar.addLoadoutBtn:Show()
    else
        sidebar.addLoadoutBtn:Hide()
        sidebar.renameBtn:Show()
        if spec == mainID then
            sidebar.setMainBtn:Hide()
            sidebar.renameBtn:SetWidth(SIDEBAR_W - 28)
            sidebar.renameBtn:ClearAllPoints()
            sidebar.renameBtn:SetPoint("TOPLEFT", 14, -240)
        else
            sidebar.renameBtn:SetWidth((SIDEBAR_W - 28 - 4) / 2)
            sidebar.renameBtn:ClearAllPoints()
            sidebar.renameBtn:SetPoint("TOPLEFT", 14, -240)
            sidebar.setMainBtn:Show()
            sidebar.setMainBtn:ClearAllPoints()
            sidebar.setMainBtn:SetPoint("TOPLEFT", sidebar.renameBtn, "TOPRIGHT", 4, 0)
        end
    end

    -- Filter row chips
    if frame.filterRow and frame.filterRow.Repaint then frame.filterRow:Repaint() end

    -- Slot cards
    local y = 0
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        local card = slotCards[slotID]
        local goals = GG:GetGoals(spec, phase, slotID)

        local visibleGoals = {}
        for _, g in ipairs(goals) do
            if RowMatchesSearch(g) then table.insert(visibleGoals, g) end
        end

        if not CardMatchesFilter(slotID, visibleGoals) then
            card:Hide()
        else
            card:Show()
            local rowsNeeded = #visibleGoals
            local h = SLOT_HEADER_H + 6 + math.max(rowsNeeded, 1) * (PICK_ROW_H + 4)
            card:SetHeight(h)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  4, -y)
            card:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, -y)
            y = y + h + 8

            card.count:SetText(rowsNeeded .. (rowsNeeded == 1 and " pick" or " picks"))

            -- Repaint header bg if this slot is the active phase's "currently equipped" one
            -- (subtle highlight if goal is equipped) — handled per-row below via row.highlight

            -- Ensure enough rows
            while #card.rows < rowsNeeded do
                local row = MakePickRow(card, slotID)
                table.insert(card.rows, row)
            end

            -- Layout + render
            for i, row in ipairs(card.rows) do
                if i <= rowsNeeded then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT",  card, "TOPLEFT",  6, -(SLOT_HEADER_H + 4 + (i-1) * (PICK_ROW_H + 4)))
                    row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -(SLOT_HEADER_H + 4 + (i-1) * (PICK_ROW_H + 4)))
                    row:SetHeight(PICK_ROW_H)
                    RenderRow(row, slotID, visibleGoals[i])
                    row:Show()
                else
                    row:Hide()
                end
            end

            -- Empty-state: show a faint hint
            if rowsNeeded == 0 then
                if not card.emptyText then
                    card.emptyText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    card.emptyText:SetPoint("CENTER", 0, -10)
                    card.emptyText:SetTextColor(unpack(P.label))
                    card.emptyText:SetText("No picks yet — click + to add")
                end
                card.emptyText:Show()
            elseif card.emptyText then
                card.emptyText:Hide()
            end
        end
    end

    scrollChild:SetHeight(math.max(y + 8, scrollFrame:GetHeight()))

    -- Header char info — name, level, class. Loadout name is shown in the
    -- sidebar instead, since loadouts are user-named and may not match class.
    if frame.header and frame.header.charInfo then
        local name = UnitName("player") or "?"
        local _, class = UnitClass("player")
        local classLabel = class and (class:lower():gsub("^%l", string.upper)) or ""
        frame.header.charInfo:SetText(name .. " · " .. classLabel .. " · " .. (UnitLevel("player") or 0))
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

function UI:Show()
    if not frame then UI:Build() end
    viewLoadoutID = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
    IT.GearGoals:SetViewedPhase(IT.GearGoals:GetViewedPhase() or IT.GearGoals:GetCurrentPhase())
    frame:Show()
    UI:Refresh()
end

--- Show the window and force the viewed phase to the *current* (notification)
--- phase, regardless of what was last viewed. Used by entry points where the
--- expected behaviour is "show me what I'm farming now" — i.e. the character
--- pane K button.
function UI:ShowAtCurrentPhase()
    if IT.GearGoals then
        IT.GearGoals:SetViewedPhase(IT.GearGoals:GetCurrentPhase())
    end
    UI:Show()
end

function UI:Hide() if frame then frame:Hide() end end

function UI:IsShown() return frame and frame:IsShown() end

function UI:Toggle()
    if frame and frame:IsShown() then UI:Hide() else UI:Show() end
end

--- Toggle variant for entry points that should snap to the active phase
--- on open (but still hide on second click).
function UI:ToggleAtCurrentPhase()
    if frame and frame:IsShown() then UI:Hide() else UI:ShowAtCurrentPhase() end
end

function UI:SetActivePhase(phase)
    IT.GearGoals:SetViewedPhase(phase)
    UI:Refresh()
end

function UI:SetFilter(mode)
    filterMode = mode
    UI:Refresh()
end

function UI:CycleLoadout()
    local loadouts = IT.GearGoals:GetLoadouts()
    if #loadouts <= 1 then return end
    local idx = 1
    for i, l in ipairs(loadouts) do
        if l.id == viewLoadoutID then idx = i; break end
    end
    viewLoadoutID = loadouts[(idx % #loadouts) + 1].id
    UI:Refresh()
end

-- ============================================================================
-- Rename / Add loadout dialog
-- ============================================================================

local function BuildRenameDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsRenameDialog", parent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(360, 140)
    d:SetPoint("CENTER")
    d:Hide()

    AddBackground(d, P.bg)
    local inner = CreateFrame("Frame", nil, d)
    inner:SetPoint("TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", -6, 6)
    AddBackground(inner, P.surface)
    AddBorder(inner, P.borderGold)

    d.title = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -10)
    d.title:SetTextColor(unpack(P.accent))

    d.label = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.label:SetPoint("TOPLEFT", 16, -40)
    d.label:SetText("Loadout name")
    d.label:SetTextColor(unpack(P.label))

    d.editBox = CreateFrame("EditBox", nil, inner)
    d.editBox:SetFontObject("GameFontHighlight")
    d.editBox:SetSize(330, 24)
    d.editBox:SetPoint("TOPLEFT", 16, -56)
    d.editBox:SetAutoFocus(true)
    d.editBox:SetScript("OnEscapePressed", function() d:Hide() end)
    d.editBox:SetScript("OnEnterPressed",  function() UI:ConfirmRenameLoadout() end)
    AddBackground(d.editBox, P.surfaceAlt)
    AddBorder(d.editBox, P.border)

    d.errorText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.errorText:SetPoint("TOPLEFT", 16, -86)
    d.errorText:SetTextColor(unpack(P.target))

    local function MakeBtn(label, anchor, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(110, 24)
        b:SetPoint("BOTTOM" .. anchor, x, 10)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(label)
        t:SetTextColor(unpack(P.value))
        return b
    end
    d.okBtn     = MakeBtn("OK",     "RIGHT", -16)
    d.cancelBtn = MakeBtn("Cancel", "LEFT",   16)
    d.okBtn:SetScript("OnClick",     function() UI:ConfirmRenameLoadout() end)
    d.cancelBtn:SetScript("OnClick", function() d:Hide() end)
    return d
end

--- Open the rename dialog. If `addMode` is true, the dialog creates a new
--- loadout instead of renaming the viewed one.
function UI:OpenRenameLoadoutDialog(addMode)
    if not renameDialog then renameDialog = BuildRenameDialog(frame) end
    renameDialog.addMode = addMode and true or false
    if addMode then
        renameDialog.title:SetText("Add loadout")
        renameDialog.editBox:SetText("")
    else
        local cur = IT.GearGoals:GetLoadoutByID(viewLoadoutID)
        renameDialog.title:SetText("Rename loadout")
        renameDialog.editBox:SetText(cur and cur.name or "")
    end
    renameDialog.errorText:SetText("")
    renameDialog:Show()
    renameDialog.editBox:SetFocus()
    renameDialog.editBox:HighlightText()
end

function UI:ConfirmRenameLoadout()
    if not renameDialog or not renameDialog:IsShown() then return end
    local name = (renameDialog.editBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        renameDialog.errorText:SetText("Name is empty.")
        return
    end
    if renameDialog.addMode then
        local entry, err = IT.GearGoals:AddLoadout(name)
        if not entry then
            renameDialog.errorText:SetText(err or "?")
            return
        end
        viewLoadoutID = entry.id
    else
        local ok, err = IT.GearGoals:RenameLoadout(viewLoadoutID, name)
        if not ok then
            renameDialog.errorText:SetText(err or "?")
            return
        end
    end
    renameDialog:Hide()
    UI:Refresh()
end

-- ============================================================================
-- Confirm-overwrite dialog (used by Phase Copy)
-- ============================================================================

local confirmDialog

local function BuildConfirmDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsConfirmDialog", parent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(380, 130)
    d:SetPoint("CENTER")
    d:Hide()

    AddBackground(d, P.bg)
    local inner = CreateFrame("Frame", nil, d)
    inner:SetPoint("TOPLEFT", 6, -6)
    inner:SetPoint("BOTTOMRIGHT", -6, 6)
    AddBackground(inner, P.surface)
    AddBorder(inner, P.borderGold)

    d.title = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    d.title:SetPoint("TOP", 0, -14)
    d.title:SetTextColor(unpack(P.accent))

    d.body = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.body:SetPoint("TOPLEFT", 16, -42)
    d.body:SetPoint("TOPRIGHT", -16, -42)
    d.body:SetJustifyH("CENTER")
    d.body:SetWordWrap(true)
    d.body:SetTextColor(unpack(P.value))

    local function MakeBtn(label, anchor, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(120, 24)
        b:SetPoint("BOTTOM" .. anchor, x, 10)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("CENTER")
        t:SetText(label)
        t:SetTextColor(unpack(P.value))
        b.text = t
        return b
    end
    d.cancelBtn  = MakeBtn("Cancel",    "LEFT",  16)
    d.confirmBtn = MakeBtn("Overwrite", "RIGHT", -16)
    -- Tint the confirm button gold to match the destructive-but-intended action.
    d.confirmBtn.text:SetTextColor(unpack(P.accent))

    d.cancelBtn:SetScript("OnClick", function() d:Hide() end)
    d.confirmBtn:SetScript("OnClick", function()
        if d.onConfirm then d.onConfirm() end
        d:Hide()
    end)
    return d
end

local function ShowConfirm(title, body, onConfirm)
    if not confirmDialog then confirmDialog = BuildConfirmDialog(frame) end
    confirmDialog.title:SetText(title)
    confirmDialog.body:SetText(body)
    confirmDialog.onConfirm = onConfirm
    confirmDialog:Show()
end

-- ============================================================================
-- Phase copy
-- ============================================================================

local function HasGoalsInPhase(loadoutID, phase)
    local goals = IT.charDB.goals
    local pb = goals and goals[loadoutID] and goals[loadoutID][phase]
    if not pb then return false end
    for _, list in pairs(pb) do
        if #list > 0 then return true end
    end
    return false
end

--- Sidebar Copy button entry point. Resolves the previous phase, checks
--- whether the destination already has picks, and either copies straight
--- or asks for confirmation first.
function UI:RequestPhaseCopy()
    local GG       = IT.GearGoals
    local viewed   = GG:GetViewedPhase()
    local prev     = GG:GetPreviousPhase(viewed)
    local loadout  = viewLoadoutID or GG:GetMainLoadoutID()

    if not prev then
        IT:Print("No previous phase to copy from.", IT.Colors.warning)
        return
    end
    if not HasGoalsInPhase(loadout, prev) then
        IT:Print("Phase " .. (GG.PHASE_LABEL[prev] or prev) .. " is empty — nothing to copy.",
            IT.Colors.warning)
        return
    end

    local fromLabel = GG.PHASE_LABEL[prev]   or prev
    local toLabel   = GG.PHASE_LABEL[viewed] or viewed
    local doCopy = function()
        local ok, err = GG:CopyPhase(loadout, prev, viewed)
        if ok then
            IT:Print("Copied " .. fromLabel .. " picks into " .. toLabel .. ".", IT.Colors.success)
        else
            IT:Print("Copy failed: " .. (err or "unknown"), IT.Colors.error)
        end
    end

    if HasGoalsInPhase(loadout, viewed) then
        ShowConfirm(
            "Overwrite " .. toLabel .. "?",
            "All current picks in " .. toLabel .. " will be replaced with " ..
            fromLabel .. "'s picks. This cannot be undone.",
            doCopy
        )
    else
        doCopy()
    end
end

-- ============================================================================
-- Build
-- ============================================================================

function UI:Build()
    frame = CreateFrame("Frame", "ItemTrackerGearGoalsFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)

    -- ESC closes the window
    table.insert(UISpecialFrames, "ItemTrackerGearGoalsFrame")

    AddBackground(frame, P.bg)

    frame.header   = BuildHeader(frame)
    frame.phaseBar = BuildPhaseBar(frame, frame.header)

    -- Sidebar (left) and main pane (right)
    sidebar = BuildSidebar(frame, frame.phaseBar)

    frame.filterRow = BuildFilterRow(frame)
    -- Sidebar's TOPRIGHT is already 8px below the phase bar (via sidebar's
    -- TOPLEFT anchor), so anchoring filterRow to that gives the right y.
    frame.filterRow:SetPoint("TOPLEFT",  sidebar, "TOPRIGHT", 8, 0)
    frame.filterRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, 0)

    -- Scroll area (right of sidebar, below filter row)
    scrollFrame = CreateFrame("ScrollFrame", "ItemTrackerGearGoalsScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame.filterRow, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(W - SIDEBAR_W - 50, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Slot cards (created lazily on first refresh, stored by slotID)
    for _, slotID in ipairs(IT.GearGoals.SLOT_ORDER) do
        slotCards[slotID] = MakeSlotCard(scrollChild, slotID)
    end

    -- React to data changes
    IT.Events:Subscribe("GEAR_GOAL_LIST_CHANGED",     function() UI:Refresh() end)
    IT.Events:Subscribe("GEAR_GOALS_PHASE_CHANGED",   function() UI:Refresh() end)
    IT.Events:Subscribe("GEAR_GOALS_LOADOUT_CHANGED", function() UI:Refresh() end)
end

function UI:Initialize()
    -- Lazy-build on first show; nothing to do at addon load.
    IT:Debug("GearGoalsUI initialized")
end
