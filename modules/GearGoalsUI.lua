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
local H              = 700      -- bumped from 620 to fit the expanded sidebar
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
local activeTab        = "LOADOUT"   -- one of "LOADOUT" / "RAIDS" / "LOOT LOG"
local ShowConfirm                -- forward-declared so RequestLoadoutDelete /
                                 -- RequestPhaseCopy (defined before the dialog)
                                 -- can reference it; assigned further down.
local RaidBucketFor              -- forward-declared so Refresh's tab-count
                                 -- code (above the RAIDS pane builder) can
                                 -- call it; assigned with the pane code.

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
    local edges = {}
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
        table.insert(edges, t)
    end
    return edges
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

-- Loadout colour palette (offered in the rename dialog). Hex strings are
-- the canonical form persisted on the loadout entry.
local SWATCH_COLORS = {
    { hex = "#FFCC33", rgb = { 1.00, 0.80, 0.20 } }, -- gold
    { hex = "#47BEF5", rgb = { 0.28, 0.74, 0.96 } }, -- cyan
    { hex = "#A335EE", rgb = { 0.64, 0.21, 0.93 } }, -- purple
    { hex = "#55CC66", rgb = { 0.33, 0.80, 0.40 } }, -- green
}

local function hexToRGB(hex)
    if not hex or type(hex) ~= "string" then return nil end
    local clean = (hex:sub(1, 1) == "#") and hex:sub(2) or hex
    if not clean:match("^%x%x%x%x%x%x$") then return nil end
    local r = tonumber(clean:sub(1, 2), 16)
    local g = tonumber(clean:sub(3, 4), 16)
    local bb = tonumber(clean:sub(5, 6), 16)
    if not (r and g and bb) then return nil end
    return { r / 255, g / 255, bb / 255 }
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
-- Top tab strip — LOADOUT / RAIDS / LOOT LOG
-- ============================================================================

local TOP_TAB_NAMES = { "LOADOUT", "RAIDS", "LOOT LOG" }
local TOP_TAB_W = 130
local TOP_TAB_H = 28
local TOP_TAB_GAP = 4

local function BuildTopTabs(parent, anchorTo)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetHeight(TOP_TAB_H + 4)
    strip:SetPoint("TOPLEFT",  anchorTo, "BOTTOMLEFT",  0, -4)
    strip:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -4)

    strip.tabs = {}
    local x = 0
    for _, name in ipairs(TOP_TAB_NAMES) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(TOP_TAB_W, TOP_TAB_H)
        b:SetPoint("TOPLEFT", x, 0)
        b.bg = AddBackground(b, P.surface)
        AddBorder(b, P.border)

        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.label:SetPoint("LEFT", 12, 0)
        b.label:SetText(name)

        -- Count badge sits to the right of the label, dim by default.
        b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.badge:SetPoint("LEFT", b.label, "RIGHT", 6, 0)
        b.badge:SetTextColor(unpack(P.label))

        b.bottomBar = b:CreateTexture(nil, "OVERLAY")
        b.bottomBar:SetPoint("BOTTOMLEFT")
        b.bottomBar:SetPoint("BOTTOMRIGHT")
        b.bottomBar:SetHeight(2)
        SetColor(b.bottomBar, { 0, 0, 0, 0 })

        b.tabName = name
        b:SetScript("OnClick", function() UI:SetTab(name) end)
        strip.tabs[name] = b
        x = x + TOP_TAB_W + TOP_TAB_GAP
    end
    return strip
end

local function PaintTopTabs(active)
    if not frame or not frame.tabStrip then return end
    for name, b in pairs(frame.tabStrip.tabs) do
        if name == active then
            SetColor(b.bg, P.accentDim)
            SetColor(b.bottomBar, P.accent)
            b.label:SetTextColor(unpack(P.accent))
        else
            SetColor(b.bg, P.surface)
            SetColor(b.bottomBar, { 0, 0, 0, 0 })
            b.label:SetTextColor(unpack(P.value))
        end
    end
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

-- Sidebar layout helpers — the sidebar is built top-to-bottom by chaining
-- each block's TOPLEFT to the previous block's BOTTOMLEFT (plus a fixed gap),
-- so adding a new block doesn't require renumbering every absolute offset
-- below it. `cursor` always points at the bottommost element of the most
-- recently added block.
local SIDEBAR_PAD_X    = 14
local SIDEBAR_GAP_INTRA = 4    -- gap between label and its value
local SIDEBAR_GAP_BLOCK = 14   -- gap between blocks

local function BuildSidebar(parent, anchorTo)
    local s = CreatePanel(parent, P.surface)
    s:SetWidth(SIDEBAR_W)
    s:SetPoint("TOPLEFT",     anchorTo, "BOTTOMLEFT", 0, -8)
    s:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",   6, 6)
    AddBorder(s, P.border)

    -- Anchor helper — always returns the new region so the caller can
    -- assign it as the next anchor.
    local function anchorBelow(region, ref, gap)
        if ref then
            region:SetPoint("TOPLEFT", ref, "BOTTOMLEFT", 0, -(gap or SIDEBAR_GAP_BLOCK))
        else
            region:SetPoint("TOPLEFT", SIDEBAR_PAD_X, -SIDEBAR_GAP_BLOCK)
        end
        return region
    end

    local function makeLabel(text)
        local f = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetText(text)
        f:SetTextColor(unpack(P.label))
        return f
    end

    local function makeValue(font, color)
        local f = s:CreateFontString(nil, "OVERLAY", font or "GameFontNormalLarge")
        f:SetTextColor(unpack(color or P.accent))
        return f
    end

    local cursor   -- updated as each block lands

    -- ── PHASE ──
    s.phaseLabel = anchorBelow(makeLabel("PHASE"), nil)
    s.phaseValue = makeValue("GameFontNormalLarge", P.accent)
    anchorBelow(s.phaseValue, s.phaseLabel, SIDEBAR_GAP_INTRA)
    s.phaseSub   = makeValue("GameFontNormalSmall", P.value)
    anchorBelow(s.phaseSub, s.phaseValue, SIDEBAR_GAP_INTRA)
    cursor = s.phaseSub

    -- ── BIS TRACKER ── rank-aware completion percentage + progress bar ────
    -- Per slot with at least one pick: score = 100 - (bestRankOwned - 1) * 20
    -- (rank 1 = 100, rank 2 = 80, rank 3 = 60, ...). No owned pick → 0.
    -- Slots without any pick are excluded from the average so an undefined
    -- slot doesn't drag the score down.
    s.statSlots      = anchorBelow(makeLabel("BIS TRACKER"), cursor)
    s.statSlotsValue = makeValue("GameFontNormalLarge", P.accent)
    anchorBelow(s.statSlotsValue, s.statSlots, SIDEBAR_GAP_INTRA)

    -- Progress bar — track + fill, fill width is set in Refresh.
    s.slotsBar = CreateFrame("Frame", nil, s)
    s.slotsBar:SetHeight(4)
    s.slotsBar:SetPoint("TOPLEFT",  s.statSlotsValue, "BOTTOMLEFT", 0, -6)
    s.slotsBar:SetPoint("RIGHT", s, "RIGHT", -SIDEBAR_PAD_X, 0)
    AddBackground(s.slotsBar, P.surfaceAlt)
    s.slotsBarFill = s.slotsBar:CreateTexture(nil, "ARTWORK")
    s.slotsBarFill:SetPoint("TOPLEFT")
    s.slotsBarFill:SetPoint("BOTTOMLEFT")
    s.slotsBarFill:SetWidth(0)
    SetColor(s.slotsBarFill, P.accent)
    cursor = s.slotsBar

    -- ── AVG ILVL ──
    s.statIlvl      = anchorBelow(makeLabel("AVG ILVL"), cursor)
    s.statIlvlValue = makeValue("GameFontNormalLarge", P.accent)
    anchorBelow(s.statIlvlValue, s.statIlvl, SIDEBAR_GAP_INTRA)
    cursor = s.statIlvlValue

    -- ── TARGETS ──
    s.statTargets      = anchorBelow(makeLabel("TARGETS"), cursor)
    s.statTargetsValue = makeValue("GameFontNormalLarge", P.target)
    anchorBelow(s.statTargetsValue, s.statTargets, SIDEBAR_GAP_INTRA)
    cursor = s.statTargetsValue

    -- ── STATUS BREAKDOWN ── three rows: dot + label + count ───────────────
    s.breakdownLabel = anchorBelow(makeLabel("STATUS BREAKDOWN"), cursor)
    cursor = s.breakdownLabel

    local function makeBreakdownRow(text, dotColor)
        local row = CreateFrame("Frame", nil, s)
        row:SetHeight(14)
        row:SetPoint("LEFT",  s, "LEFT",  SIDEBAR_PAD_X, 0)
        row:SetPoint("RIGHT", s, "RIGHT", -SIDEBAR_PAD_X, 0)

        row.dot = row:CreateTexture(nil, "ARTWORK")
        row.dot:SetSize(6, 6)
        row.dot:SetPoint("LEFT", 0, 0)
        SetColor(row.dot, dotColor)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.dot, "RIGHT", 8, 0)
        row.label:SetText(text)
        row.label:SetTextColor(unpack(P.value))

        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count:SetPoint("RIGHT")
        row.count:SetTextColor(unpack(P.value))
        return row
    end

    s.breakdownOwned    = makeBreakdownRow("Owned",                P.success)
    s.breakdownTargeted = makeBreakdownRow("Targeted",             P.target)
    s.breakdownLocked   = makeBreakdownRow("Locked (future phase)", P.locked)
    anchorBelow(s.breakdownOwned,    cursor,                SIDEBAR_GAP_INTRA + 2)
    anchorBelow(s.breakdownTargeted, s.breakdownOwned,      SIDEBAR_GAP_INTRA)
    anchorBelow(s.breakdownLocked,   s.breakdownTargeted,   SIDEBAR_GAP_INTRA)
    cursor = s.breakdownLocked

    -- ── LOADOUT ── (panel: name button + rename / set-main / add-second) ──
    s.loadoutLabel = anchorBelow(makeLabel("LOADOUT"), cursor)

    s.loadoutBtn = CreateFrame("Button", nil, s)
    s.loadoutBtn:SetSize(SIDEBAR_W - 28, 26)
    anchorBelow(s.loadoutBtn, s.loadoutLabel, SIDEBAR_GAP_INTRA)
    s.loadoutBtn.bg = AddBackground(s.loadoutBtn, P.surfaceAlt)
    AddBorder(s.loadoutBtn, P.border)
    -- Loadout colour swatch (8×8 square left of the name). Painted from the
    -- loadout's `color` field in Refresh; defaults to gold for the main
    -- loadout, otherwise surfaceAlt (matches button background = invisible).
    s.loadoutBtn.colorSwatch = s.loadoutBtn:CreateTexture(nil, "OVERLAY")
    s.loadoutBtn.colorSwatch:SetSize(10, 10)
    s.loadoutBtn.colorSwatch:SetPoint("LEFT", 8, 0)
    SetColor(s.loadoutBtn.colorSwatch, P.surfaceAlt)

    -- Static "click to switch" cue on the right edge — using ASCII because
    -- WoW's default font doesn't cover the Arrows block (U+219x) so a
    -- proper ↔ would render as a blank box.
    s.loadoutBtn.chevron = s.loadoutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.loadoutBtn.chevron:SetPoint("RIGHT", -8, 0)
    s.loadoutBtn.chevron:SetText("<>")
    s.loadoutBtn.chevron:SetTextColor(unpack(P.label))

    s.loadoutBtn.text = s.loadoutBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.loadoutBtn.text:SetPoint("LEFT", 24, 0)
    s.loadoutBtn.text:SetPoint("RIGHT", s.loadoutBtn.chevron, "LEFT", -6, 0)
    s.loadoutBtn.text:SetJustifyH("LEFT")
    s.loadoutBtn.text:SetWordWrap(false)
    s.loadoutBtn.text:SetTextColor(unpack(P.value))
    s.loadoutBtn:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
    s.loadoutBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.loadoutBtn:SetScript("OnClick", function() UI:CycleLoadout() end)

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
    s.renameBtn = MakeAction("Edit", function() UI:OpenRenameLoadoutDialog() end)
    anchorBelow(s.renameBtn, s.loadoutBtn, SIDEBAR_GAP_INTRA)

    s.setMainBtn = MakeAction("Set main", function()
        IT.GearGoals:SetMainLoadout(viewLoadoutID)
        UI:Refresh()
    end)
    s.setMainBtn:SetPoint("TOPLEFT", s.renameBtn, "TOPRIGHT", 4, 0)

    s.addLoadoutBtn = MakeAction("+ Add second loadout", function()
        UI:OpenRenameLoadoutDialog(true)   -- true = add mode
    end)
    s.addLoadoutBtn:SetPoint("TOPLEFT", s.renameBtn, "TOPLEFT", 0, 0)
    s.addLoadoutBtn:SetWidth(SIDEBAR_W - 28)
    cursor = s.renameBtn  -- same y row as setMainBtn / addLoadoutBtn

    -- ── CURRENT PHASE ── (label + value + "set as current" button) ────────
    s.currentPhaseLabel = anchorBelow(makeLabel("CURRENT PHASE"), cursor)
    s.currentPhaseValue = makeValue("GameFontNormal", P.accent)
    anchorBelow(s.currentPhaseValue, s.currentPhaseLabel, SIDEBAR_GAP_INTRA)

    s.setCurrentBtn = CreateFrame("Button", nil, s)
    s.setCurrentBtn:SetSize(SIDEBAR_W - 28, 26)
    anchorBelow(s.setCurrentBtn, s.currentPhaseValue, SIDEBAR_GAP_INTRA)
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
    cursor = s.setCurrentBtn

    -- ── PHASE ACTIONS ── ("Copy from <previous phase>", Import / Export) ─
    s.phaseActionsLabel = anchorBelow(makeLabel("PHASE ACTIONS"), cursor)

    s.copyPhaseBtn = CreateFrame("Button", nil, s)
    s.copyPhaseBtn:SetSize(SIDEBAR_W - 28, 26)
    anchorBelow(s.copyPhaseBtn, s.phaseActionsLabel, SIDEBAR_GAP_INTRA)
    s.copyPhaseBtn.bg = AddBackground(s.copyPhaseBtn, P.surfaceAlt)
    AddBorder(s.copyPhaseBtn, P.borderGold)
    s.copyPhaseBtn.text = s.copyPhaseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.copyPhaseBtn.text:SetPoint("CENTER")
    s.copyPhaseBtn.text:SetTextColor(unpack(P.accent))
    s.copyPhaseBtn:SetScript("OnEnter", function(self) SetColor(self.bg, P.accentDim) end)
    s.copyPhaseBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.copyPhaseBtn:SetScript("OnClick", function() UI:RequestPhaseCopy() end)

    -- Import BiS + Export side-by-side, half width each.
    local halfW = (SIDEBAR_W - 28 - 4) / 2

    s.importBisBtn = CreateFrame("Button", nil, s)
    s.importBisBtn:SetSize(halfW, 24)
    anchorBelow(s.importBisBtn, s.copyPhaseBtn, SIDEBAR_GAP_INTRA)
    s.importBisBtn.bg = AddBackground(s.importBisBtn, P.surfaceAlt)
    AddBorder(s.importBisBtn, P.border)
    s.importBisBtn.text = s.importBisBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.importBisBtn.text:SetPoint("CENTER")
    s.importBisBtn.text:SetText("Import")
    s.importBisBtn.text:SetTextColor(unpack(P.value))
    s.importBisBtn:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
    s.importBisBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.importBisBtn:SetScript("OnClick", function() UI:OpenImportBiSDialog() end)

    s.exportBtn = CreateFrame("Button", nil, s)
    s.exportBtn:SetSize(halfW, 24)
    s.exportBtn:SetPoint("TOPLEFT", s.importBisBtn, "TOPRIGHT", 4, 0)
    s.exportBtn.bg = AddBackground(s.exportBtn, P.surfaceAlt)
    AddBorder(s.exportBtn, P.border)
    s.exportBtn.text = s.exportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    s.exportBtn.text:SetPoint("CENTER")
    s.exportBtn.text:SetText("Export")
    s.exportBtn.text:SetTextColor(unpack(P.value))
    s.exportBtn:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
    s.exportBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    s.exportBtn:SetScript("OnClick", function() UI:OpenExportDialog() end)

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

    -- Reorder + remove use `row.slotID` (set in RenderRow) rather than the
    -- closure value, because the same row is reused for the RAIDS pane
    -- where successive renders may show goals from different slots.
    row.upBtn:SetScript("OnClick", function()
        if not row.goal or not row.slotID then return end
        local viewed = IT.GearGoals:GetViewedPhase()
        local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
        IT.GearGoals:MoveGoal(spec, viewed, row.slotID, row.goal.itemID, -1)
        UI:Refresh()
    end)
    row.dnBtn:SetScript("OnClick", function()
        if not row.goal or not row.slotID then return end
        local viewed = IT.GearGoals:GetViewedPhase()
        local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
        IT.GearGoals:MoveGoal(spec, viewed, row.slotID, row.goal.itemID, 1)
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

    -- Right-click: remove (uses row.slotID set in RenderRow)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and self.goal and self.slotID then
            local viewed = IT.GearGoals:GetViewedPhase()
            local spec   = viewLoadoutID or IT.GearGoals:GetMainLoadoutID()
            IT.GearGoals:RemoveGoal(spec, viewed, self.slotID, self.goal.itemID)
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

    -- Slot-validation used to hard-reject mismatched INVTYPEs. That blocked
    -- legitimate edge cases (relics on slot 18, ranged weapons on Hunter MH,
    -- items with INVTYPEs we hadn't mapped) and produced friction when the
    -- user knew exactly what they wanted. We trust the user's pick now;
    -- status detection will simply not auto-bind a goal whose item never
    -- actually appears in the chosen slot.

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
    row.slotID   = slotID   -- per-render slot so RAIDS view's mixed-slot rows work
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

    PaintTopTabs(activeTab)
    PaintPhaseTabs(phase, activePhase)

    -- Show only the active pane.
    frame.loadoutPane:SetShown(activeTab == "LOADOUT")
    frame.raidsPane:SetShown(activeTab == "RAIDS")
    frame.lootLogPane:SetShown(activeTab == "LOOT LOG")

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

    -- BiS tracker score (per viewed phase) + targets count.
    --   Per slot with at least one pick:
    --       bestRankOwned = lowest rank with status EQUIPPED/OWNED/COVERED
    --       slotScore     = max(0, 100 - (bestRankOwned - 1) * 20)
    --       (no owned pick → 0)
    --   Final score = average across slots that have picks defined.
    -- Goals iterate in array order; NormalizeRanks keeps array index ==
    -- goal.rank, so the first goal we hit with an owned status is the best.
    local PER_RANK_PENALTY = 20
    local bisScoreSum, bisSlotCount, totalTargets = 0, 0, 0
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        local goals = GG:GetGoals(spec, phase, slotID)
        if #goals > 0 then
            bisSlotCount = bisSlotCount + 1
            local bestRank
            for _, g in ipairs(goals) do
                local status = GG:StatusFor(spec, phase, slotID, g)
                if status == GG.STATUS.TARGET then
                    totalTargets = totalTargets + 1
                end
                if not bestRank
                   and (status == GG.STATUS.EQUIPPED
                        or status == GG.STATUS.OWNED
                        or status == GG.STATUS.COVERED) then
                    bestRank = g.rank
                end
            end
            if bestRank then
                bisScoreSum = bisScoreSum
                    + math.max(0, 100 - (bestRank - 1) * PER_RANK_PENALTY)
            end
            -- else: slot contributes 0
        end
    end
    local bisPct = (bisSlotCount > 0)
        and math.floor(bisScoreSum / bisSlotCount + 0.5) or 0
    sidebar.statSlotsValue:SetText(bisPct .. "%")
    sidebar.statTargetsValue:SetText(tostring(totalTargets))

    -- BiS progress bar — fills proportional to bisPct.
    local trackW = sidebar.slotsBar:GetWidth() or 0
    if trackW > 0 then
        sidebar.slotsBarFill:SetWidth(math.max(0, trackW * (bisPct / 100)))
    end

    -- Avg ilvl: average of currently-equipped tracked slots, character-wide.
    -- Independent of the viewed loadout/phase — it's "what am I wearing".
    local ilvlSum, ilvlCount = 0, 0
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        local eq = GG:GetEquipped(slotID)
        if eq and eq.ilvl and eq.ilvl > 0 then
            ilvlSum   = ilvlSum   + eq.ilvl
            ilvlCount = ilvlCount + 1
        end
    end
    if ilvlCount > 0 then
        sidebar.statIlvlValue:SetText(tostring(math.floor(ilvlSum / ilvlCount + 0.5)))
    else
        sidebar.statIlvlValue:SetText("-")
    end

    -- Status breakdown — across *every* phase of the viewed loadout. Gives
    -- a holistic view of progress that the per-phase TARGETS pill can't.
    local owned, targeted, locked = 0, 0, 0
    local loadoutGoals = IT.charDB.goals and IT.charDB.goals[spec]
    if loadoutGoals then
        for ph, bySlot in pairs(loadoutGoals) do
            for slotID, list in pairs(bySlot) do
                for _, g in ipairs(list) do
                    local status = GG:StatusFor(spec, ph, slotID, g)
                    if status == GG.STATUS.TARGET then
                        targeted = targeted + 1
                    elseif status == GG.STATUS.LOCKED then
                        locked = locked + 1
                    elseif status == GG.STATUS.EQUIPPED
                        or status == GG.STATUS.OWNED
                        or status == GG.STATUS.COVERED then
                        owned = owned + 1
                    end
                end
            end
        end
    end
    sidebar.breakdownOwned.count:SetText(tostring(owned))
    sidebar.breakdownTargeted.count:SetText(tostring(targeted))
    sidebar.breakdownLocked.count:SetText(tostring(locked))

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

    -- Loadout colour swatch: explicit colour wins, else gold for main /
    -- transparent (button background) for alt without a colour set.
    local swatchRGB = viewing and hexToRGB(viewing.color)
    if swatchRGB then
        SetColor(sidebar.loadoutBtn.colorSwatch, swatchRGB)
    elseif spec == mainID then
        SetColor(sidebar.loadoutBtn.colorSwatch, P.accent)
    else
        SetColor(sidebar.loadoutBtn.colorSwatch, P.surfaceAlt)
    end

    -- Show / hide the action buttons. The relative anchors set by
    -- BuildSidebar (renameBtn -> loadoutBtn:BOTTOMLEFT, setMainBtn ->
    -- renameBtn:TOPRIGHT, addLoadoutBtn -> renameBtn:TOPLEFT) stay intact;
    -- here we only flip visibility and width.
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
        else
            sidebar.renameBtn:SetWidth((SIDEBAR_W - 28 - 4) / 2)
            sidebar.setMainBtn:Show()
        end
    end

    -- Filter row chips
    if frame.filterRow and frame.filterRow.Repaint then frame.filterRow:Repaint() end

    -- Tab counts (badges to the right of each tab label).
    local loadoutBadge, raidBadge, lootLogBadge = 0, 0, 0
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        local goals = GG:GetGoals(spec, phase, slotID)
        if #goals > 0 then loadoutBadge = loadoutBadge + 1 end
    end
    do
        local seenRaids = {}
        for _, slotID in ipairs(GG.SLOT_ORDER) do
            for _, g in ipairs(GG:GetGoals(spec, phase, slotID)) do
                local bucket = RaidBucketFor(g.itemID)
                if not seenRaids[bucket] then
                    seenRaids[bucket] = true
                    raidBadge = raidBadge + 1
                end
            end
        end
    end
    if IT.LootHistory and IT.LootHistory.GetAll and IT.GearGoals.FindAllMatches then
        local Tokens = IT.GearGoalsTokens
        for _, e in ipairs(IT.LootHistory:GetAll()) do
            if e.itemID then
                local hasMatch = #IT.GearGoals:FindAllMatches(e.itemID) > 0
                if not hasMatch and Tokens and Tokens:IsToken(e.itemID) then
                    hasMatch = #IT.GearGoals:FindAllMatchesForToken(e.itemID) > 0
                end
                if hasMatch then lootLogBadge = lootLogBadge + 1 end
            end
        end
    end
    if frame.tabStrip then
        frame.tabStrip.tabs["LOADOUT"].badge:SetText(tostring(loadoutBadge))
        frame.tabStrip.tabs["RAIDS"].badge:SetText(tostring(raidBadge))
        frame.tabStrip.tabs["LOOT LOG"].badge:SetText(tostring(lootLogBadge))
    end

    -- Render the active pane
    if activeTab == "RAIDS" then
        UI:RenderRaidsPane()
    elseif activeTab == "LOOT LOG" then
        UI:RenderLootLogPane()
    else
        -- LOADOUT: slot cards
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
    end

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

--- Switch the active top tab. Hides the panes that aren't active and
--- triggers a refresh which re-renders the visible one.
function UI:SetTab(name)
    if name ~= "LOADOUT" and name ~= "RAIDS" and name ~= "LOOT LOG" then return end
    activeTab = name
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

local SWATCH_SIZE = 22
local SWATCH_GAP  = 8

local function BuildRenameDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsRenameDialog", parent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(360, 200)   -- taller to fit the colour-swatch row
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

    -- Colour-swatch row — four predefined colours plus a "no colour" reset
    -- swatch (the surfaceAlt swatch with a tiny strikethrough). Selecting a
    -- swatch sets `d.pendingColor`; persisted on confirm.
    d.swatchLabel = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.swatchLabel:SetPoint("TOPLEFT", 16, -110)
    d.swatchLabel:SetText("Colour")
    d.swatchLabel:SetTextColor(unpack(P.label))

    d.swatches = {}

    local function buildSwatch(rgb, hex, prevAnchor)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(SWATCH_SIZE, SWATCH_SIZE)
        if prevAnchor then
            b:SetPoint("LEFT", prevAnchor, "RIGHT", SWATCH_GAP, 0)
        else
            b:SetPoint("TOPLEFT", d.swatchLabel, "TOPRIGHT", 14, 4)
        end
        AddBackground(b, rgb)
        AddBorder(b, P.border)

        -- Active-state visuals — two complementary cues so the selected
        -- swatch reads at a glance:
        --   1) a 2px white border around the swatch
        --   2) a small accent pip extending below the swatch
        b.activeBorderEdges = AddBorder(b, { 1, 1, 1, 1 }, 2)
        for _, t in ipairs(b.activeBorderEdges) do t:Hide() end

        b.activePip = b:CreateTexture(nil, "OVERLAY")
        b.activePip:SetSize(SWATCH_SIZE - 8, 3)
        b.activePip:SetPoint("TOP", b, "BOTTOM", 0, -3)
        SetColor(b.activePip, P.accent)
        b.activePip:Hide()

        b.hex = hex
        b:SetScript("OnEnter", function(self)
            -- Subtle hover hint independent of selection state
            for _, t in ipairs(self.activeBorderEdges) do
                if not self._isActive then SetColor(t, { 1, 1, 1, 0.4 }); t:Show() end
            end
        end)
        b:SetScript("OnLeave", function(self)
            if not self._isActive then
                for _, t in ipairs(self.activeBorderEdges) do t:Hide() end
            end
        end)
        b:SetScript("OnClick", function()
            d.pendingColor = hex
            UI:RepaintRenameSwatches()
        end)
        return b
    end

    -- "No colour" first (clears the loadout colour), then the four palette colours.
    d.swatchNone = buildSwatch(P.surfaceAlt, nil, nil)
    -- Tiny crossbar to indicate the "no colour" swatch
    local cross = d.swatchNone:CreateTexture(nil, "OVERLAY")
    cross:SetSize(SWATCH_SIZE - 6, 1)
    cross:SetPoint("CENTER")
    SetColor(cross, P.label)
    table.insert(d.swatches, d.swatchNone)

    local prev = d.swatchNone
    for _, c in ipairs(SWATCH_COLORS) do
        local b = buildSwatch(c.rgb, c.hex, prev)
        table.insert(d.swatches, b)
        prev = b
    end

    -- Bottom-row buttons. Delete sits between Cancel and OK and uses the
    -- target/pink text colour to read as destructive. Visibility set in
    -- OpenRenameLoadoutDialog.
    local function MakeBtn(label, anchor, x, width)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(width or 110, 24)
        b:SetPoint("BOTTOM" .. anchor, x, 10)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(unpack(P.value))
        return b
    end
    d.okBtn     = MakeBtn("OK",     "RIGHT", -16)
    d.deleteBtn = MakeBtn("Delete", "RIGHT", -132, 80)   -- 80 wide, 132 = OK width 110 + gap 6 + own width nudge
    d.deleteBtn.text:SetTextColor(unpack(P.target))
    d.cancelBtn = MakeBtn("Cancel", "LEFT", 16)

    d.okBtn:SetScript("OnClick",     function() UI:ConfirmRenameLoadout() end)
    d.cancelBtn:SetScript("OnClick", function() d:Hide() end)
    d.deleteBtn:SetScript("OnClick", function() UI:RequestLoadoutDelete() end)

    return d
end

--- Paint the selection state on every swatch: white border + accent pip
--- on the active one, hidden on the rest. Active = swatch.hex matches
--- renameDialog.pendingColor (nil = the no-colour swatch).
function UI:RepaintRenameSwatches()
    if not renameDialog or not renameDialog.swatches then return end
    for _, b in ipairs(renameDialog.swatches) do
        local active = (b.hex == renameDialog.pendingColor)
        b._isActive = active
        for _, t in ipairs(b.activeBorderEdges) do
            if active then
                SetColor(t, { 1, 1, 1, 1 })
                t:Show()
            else
                t:Hide()
            end
        end
        if active then b.activePip:Show() else b.activePip:Hide() end
    end
end

--- Open the rename dialog. If `addMode` is true, the dialog creates a new
--- loadout instead of renaming the viewed one.
function UI:OpenRenameLoadoutDialog(addMode)
    if not renameDialog then renameDialog = BuildRenameDialog(frame) end
    renameDialog.addMode = addMode and true or false
    if addMode then
        renameDialog.title:SetText("Add loadout")
        renameDialog.editBox:SetText("")
        renameDialog.pendingColor = nil
        renameDialog.deleteBtn:Hide()
    else
        local cur = IT.GearGoals:GetLoadoutByID(viewLoadoutID)
        renameDialog.title:SetText("Edit loadout")
        renameDialog.editBox:SetText(cur and cur.name or "")
        renameDialog.pendingColor = cur and cur.color or nil
        -- Delete is offered only when there's a survivor to keep.
        if #IT.GearGoals:GetLoadouts() > 1 then
            renameDialog.deleteBtn:Show()
        else
            renameDialog.deleteBtn:Hide()
        end
    end
    renameDialog.errorText:SetText("")
    UI:RepaintRenameSwatches()
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
        if renameDialog.pendingColor then
            IT.GearGoals:SetLoadoutColor(entry.id, renameDialog.pendingColor)
        end
    else
        local ok, err = IT.GearGoals:RenameLoadout(viewLoadoutID, name)
        if not ok then
            renameDialog.errorText:SetText(err or "?")
            return
        end
        -- Apply colour change if the user picked a different swatch.
        local cur = IT.GearGoals:GetLoadoutByID(viewLoadoutID)
        if (cur and cur.color or nil) ~= renameDialog.pendingColor then
            IT.GearGoals:SetLoadoutColor(viewLoadoutID, renameDialog.pendingColor)
        end
    end
    renameDialog:Hide()
    UI:Refresh()
end

--- Delete-button entry point. Confirms via the existing ShowConfirm dialog
--- (same pattern Phase Copy uses) and then removes the viewed loadout.
function UI:RequestLoadoutDelete()
    if not renameDialog or not renameDialog:IsShown() then return end
    local cur = IT.GearGoals:GetLoadoutByID(viewLoadoutID)
    local label = (cur and cur.name) or viewLoadoutID or "?"
    -- Hide the rename dialog first so the confirm popup isn't dimmed behind it.
    renameDialog:Hide()
    ShowConfirm(
        "Delete '" .. label .. "'?",
        "All picks on this loadout will be removed permanently. " ..
        "This cannot be undone.",
        function()
            local ok, err = IT.GearGoals:RemoveLoadout(viewLoadoutID)
            if ok then
                viewLoadoutID = IT.GearGoals:GetMainLoadoutID()
                IT:Print("Deleted loadout '" .. label .. "'.", IT.Colors.success)
                UI:Refresh()
            else
                IT:Print("Couldn't delete loadout: " .. (err or "?"), IT.Colors.error)
            end
        end,
        "Delete"
    )
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

ShowConfirm = function(title, body, onConfirm, confirmLabel)
    if not confirmDialog then confirmDialog = BuildConfirmDialog(frame) end
    confirmDialog.title:SetText(title)
    confirmDialog.body:SetText(body)
    confirmDialog.confirmBtn.text:SetText(confirmLabel or "Overwrite")
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
-- Import BiS (TBCA_BIS plugin) and Export dialogs
-- ============================================================================

local importDialog
local importState = { source = "tbca", spec = nil, mode = "merge", string = "" }
local IMPORT_TOP_N = 3

local function BuildImportDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsImportDialog", parent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(420, 340)
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
    d.title:SetText("Import")

    -- Source toggle row (top): TBCA vs paste-string
    local function MakeSourceBtn(label, source, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(190, 24)
        b:SetPoint("TOPLEFT", x, -42)
        b.bg = AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(unpack(P.value))
        b.source = source
        b:SetScript("OnClick", function()
            importState.source = source
            UI:RepaintImportDialog()
        end)
        return b
    end
    d.tbcaBtn   = MakeSourceBtn("From AtlasLoot",   "tbca",   16)
    d.stringBtn = MakeSourceBtn("From paste",       "string", 212)

    -- ── TBCA-mode content ──────────────────────────────────────────────
    d.tbcaSection = CreateFrame("Frame", nil, inner)
    d.tbcaSection:SetPoint("TOPLEFT",  16, -78)
    d.tbcaSection:SetPoint("TOPRIGHT", -16, -78)
    d.tbcaSection:SetHeight(110)

    d.specLabel = d.tbcaSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.specLabel:SetPoint("TOPLEFT", 0, 0)
    d.specLabel:SetText("Spec")
    d.specLabel:SetTextColor(unpack(P.label))

    d.specBtn = CreateFrame("Button", nil, d.tbcaSection)
    d.specBtn:SetPoint("TOPLEFT", 0, -16)
    d.specBtn:SetPoint("RIGHT")
    d.specBtn:SetHeight(26)
    d.specBtn.bg = AddBackground(d.specBtn, P.surfaceAlt)
    AddBorder(d.specBtn, P.border)
    d.specBtn.text = d.specBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.specBtn.text:SetPoint("LEFT", 8, 0)
    d.specBtn.text:SetTextColor(unpack(P.value))
    d.specBtn.cycleHint = d.specBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.specBtn.cycleHint:SetPoint("RIGHT", -8, 0)
    d.specBtn.cycleHint:SetText("<>")
    d.specBtn.cycleHint:SetTextColor(unpack(P.label))
    d.specBtn:SetScript("OnEnter", function(self) SetColor(self.bg, { 0.16, 0.16, 0.20, 1 }) end)
    d.specBtn:SetScript("OnLeave", function(self) SetColor(self.bg, P.surfaceAlt) end)
    d.specBtn:SetScript("OnClick", function() UI:CycleImportSpec() end)

    d.tbcaHint = d.tbcaSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.tbcaHint:SetPoint("TOPLEFT", 0, -54)
    d.tbcaHint:SetWidth(380)
    d.tbcaHint:SetJustifyH("LEFT")
    d.tbcaHint:SetText(string.format(
        "Top %d BiS picks per slot will be added.", IMPORT_TOP_N))
    d.tbcaHint:SetTextColor(unpack(P.label))

    -- ── String-mode content ───────────────────────────────────────────
    d.stringSection = CreateFrame("Frame", nil, inner)
    d.stringSection:SetPoint("TOPLEFT",  16, -78)
    d.stringSection:SetPoint("TOPRIGHT", -16, -78)
    d.stringSection:SetHeight(110)

    d.stringLabel = d.stringSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.stringLabel:SetPoint("TOPLEFT", 0, 0)
    d.stringLabel:SetText("Paste exported string")
    d.stringLabel:SetTextColor(unpack(P.label))

    local stringScroll = CreateFrame("ScrollFrame", nil, d.stringSection, "UIPanelScrollFrameTemplate")
    stringScroll:SetPoint("TOPLEFT",  0, -18)
    stringScroll:SetPoint("BOTTOMRIGHT", -22, 24)
    AddBackground(stringScroll, P.surfaceAlt)
    AddBorder(stringScroll, P.border)
    d.stringScroll = stringScroll

    d.stringEdit = CreateFrame("EditBox", nil, stringScroll)
    d.stringEdit:SetMultiLine(true)
    d.stringEdit:SetFontObject("ChatFontNormal")
    d.stringEdit:SetWidth(360)
    d.stringEdit:SetHeight(64)
    d.stringEdit:SetAutoFocus(false)
    d.stringEdit:SetTextColor(unpack(P.value))
    d.stringEdit:SetScript("OnEscapePressed", function() d:Hide() end)
    d.stringEdit:SetScript("OnTextChanged", function(self) UI:RepaintImportDialog() end)
    stringScroll:SetScrollChild(d.stringEdit)

    d.stringPreview = d.stringSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.stringPreview:SetPoint("BOTTOMLEFT", 0, 0)
    d.stringPreview:SetPoint("BOTTOMRIGHT", 0, 0)
    d.stringPreview:SetJustifyH("LEFT")
    d.stringPreview:SetTextColor(unpack(P.label))

    -- ── Mode toggle (shared across both source modes) ─────────────────
    d.modeLabel = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.modeLabel:SetPoint("TOPLEFT", 16, -200)
    d.modeLabel:SetText("Mode")
    d.modeLabel:SetTextColor(unpack(P.label))

    local function MakeModeBtn(label, mode, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(190, 24)
        b:SetPoint("TOPLEFT", x, -218)
        b.bg = AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(unpack(P.value))
        b.mode = mode
        b:SetScript("OnClick", function()
            importState.mode = mode
            UI:RepaintImportDialog()
        end)
        return b
    end
    d.mergeBtn     = MakeModeBtn("Merge",     "merge",     16)
    d.overwriteBtn = MakeModeBtn("Overwrite", "overwrite", 212)

    -- Error / status line above the buttons
    d.errorText = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.errorText:SetPoint("BOTTOMLEFT",  16, 44)
    d.errorText:SetPoint("BOTTOMRIGHT", -16, 44)
    d.errorText:SetJustifyH("LEFT")
    d.errorText:SetTextColor(unpack(P.target))

    -- Bottom row buttons
    local function MakeBtn(label, anchor, x)
        local b = CreateFrame("Button", nil, inner)
        b:SetSize(110, 24)
        b:SetPoint("BOTTOM" .. anchor, x, 10)
        AddBackground(b, P.surfaceAlt)
        AddBorder(b, P.border)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(unpack(P.value))
        return b
    end
    d.importBtn = MakeBtn("Import", "RIGHT", -16)
    d.cancelBtn = MakeBtn("Cancel", "LEFT", 16)
    d.importBtn:SetScript("OnClick", function() UI:ConfirmImport() end)
    d.cancelBtn:SetScript("OnClick", function() d:Hide() end)
    return d
end

--- Re-paint every dynamic surface on the import dialog: source toggle,
--- mode toggle, spec name, and the live preview for the paste-string mode.
function UI:RepaintImportDialog()
    if not importDialog then return end

    -- Source toggle: highlight active button + show/hide section
    for _, b in ipairs({ importDialog.tbcaBtn, importDialog.stringBtn }) do
        if b.source == importState.source then
            SetColor(b.bg, P.accentDim)
            b.text:SetTextColor(unpack(P.accent))
        else
            SetColor(b.bg, P.surfaceAlt)
            b.text:SetTextColor(unpack(P.value))
        end
    end
    importDialog.tbcaSection:SetShown(importState.source == "tbca")
    importDialog.stringSection:SetShown(importState.source == "string")

    -- Spec cycle button
    importDialog.specBtn.text:SetText(importState.spec or "?")

    -- Mode toggle highlight
    for _, b in ipairs({ importDialog.mergeBtn, importDialog.overwriteBtn }) do
        if b.mode == importState.mode then
            SetColor(b.bg, P.accentDim)
            b.text:SetTextColor(unpack(P.accent))
        else
            SetColor(b.bg, P.surfaceAlt)
            b.text:SetTextColor(unpack(P.value))
        end
    end

    -- Paste-string preview: parse on every keystroke so the user sees
    -- "valid: <name> · <phase>, N picks" or an error before clicking Import.
    if importState.source == "string" then
        local raw = importDialog.stringEdit:GetText() or ""
        if raw:gsub("%s+", "") == "" then
            importDialog.stringPreview:SetText("")
            importDialog.stringPreview:SetTextColor(unpack(P.label))
        else
            local decoded, err = IT.GearGoals:DecodePhase(raw)
            if decoded then
                local count = 0
                for _, picks in pairs(decoded.slots or {}) do count = count + #picks end
                local viewedPhase = IT.GearGoals:GetViewedPhase()
                local phaseLabel  = IT.GearGoals.PHASE_LABEL[viewedPhase] or viewedPhase
                local sourceLabel = IT.GearGoals.PHASE_LABEL[decoded.phase] or decoded.phase
                local destNote
                if decoded.phase == viewedPhase then
                    destNote = ""
                else
                    destNote = string.format(" . importing into %s (current view)", phaseLabel)
                end
                importDialog.stringPreview:SetText(string.format(
                    "Looks valid: %s . %s, %d pick%s%s",
                    decoded.name, sourceLabel, count,
                    count == 1 and "" or "s", destNote))
                importDialog.stringPreview:SetTextColor(unpack(P.success))
            else
                importDialog.stringPreview:SetText("Doesn't parse: " .. (err or "?"))
                importDialog.stringPreview:SetTextColor(unpack(P.target))
            end
        end
    end
    importDialog.errorText:SetText("")
end

function UI:OpenImportDialog()
    if not importDialog then importDialog = BuildImportDialog(frame) end

    -- Default source to TBCA when available; otherwise jump to string.
    local AL = IT.GearGoalsAtlasLoot
    local specs = (AL and AL.GetTBCASpecsForClass) and AL:GetTBCASpecsForClass() or {}
    if importState.source == "tbca" and #specs == 0 then
        importState.source = "string"
    end
    -- Keep last spec selection if valid, else first available
    if #specs > 0 then
        local ok = false
        for _, s in ipairs(specs) do if s == importState.spec then ok = true; break end end
        if not ok then importState.spec = specs[1] end
    end
    importState.mode = importState.mode or "merge"

    importDialog.stringEdit:SetText(importState.string or "")
    UI:RepaintImportDialog()
    importDialog:Show()
end

function UI:CycleImportSpec()
    local AL = IT.GearGoalsAtlasLoot
    local specs = (AL and AL.GetTBCASpecsForClass) and AL:GetTBCASpecsForClass() or {}
    if #specs <= 1 then return end
    local idx = 1
    for i, s in ipairs(specs) do if s == importState.spec then idx = i; break end end
    importState.spec = specs[(idx % #specs) + 1]
    UI:RepaintImportDialog()
end

--- Dispatch to the active source. Both paths apply to the *currently viewed*
--- loadout/phase regardless of any phase recorded inside an exported string.
function UI:ConfirmImport()
    if not importDialog or not importDialog:IsShown() then return end
    local GG        = IT.GearGoals
    local loadoutID = viewLoadoutID or GG:GetMainLoadoutID()
    local phase     = GG:GetViewedPhase()

    if importState.source == "tbca" then
        local AL = IT.GearGoalsAtlasLoot
        if not AL or not importState.spec then
            importDialog.errorText:SetText("AtlasLoot TBCA_BIS not available.")
            return
        end
        if importState.mode == "overwrite" and IT.charDB.goals[loadoutID] then
            IT.charDB.goals[loadoutID][phase] = {}
        end
        local added, skipped = 0, 0
        for _, slotID in ipairs(GG.SLOT_ORDER) do
            local items = AL:GetBiSItemsForSpec(importState.spec, phase, slotID, IMPORT_TOP_N)
            if items then
                for _, itemID in ipairs(items) do
                    local entry = GG:AddGoal(loadoutID, phase, slotID, itemID)
                    if entry then added = added + 1 else skipped = skipped + 1 end
                end
            end
        end
        importDialog:Hide()
        UI:Refresh()
        IT:Print(string.format("Imported BiS from %s: %d added, %d skipped.",
            importState.spec, added, skipped), IT.Colors.success)
    else
        -- String source
        local raw = importDialog.stringEdit:GetText() or ""
        importState.string = raw   -- remember between dialog opens
        local decoded, err = GG:DecodePhase(raw)
        if not decoded then
            importDialog.errorText:SetText("Couldn't parse: " .. (err or "?"))
            return
        end
        local ok, added, skipped = GG:ApplyDecodedPhase(loadoutID, phase, decoded, importState.mode)
        if not ok then
            importDialog.errorText:SetText("Couldn't import: " .. (added or "?"))
            return
        end
        importDialog:Hide()
        UI:Refresh()
        IT:Print(string.format("Imported %d picks (%d skipped) into %s.",
            added, skipped, phase), IT.Colors.success)
    end
end

-- Backwards-compat alias for any external callers / older slash branches.
UI.OpenImportBiSDialog = UI.OpenImportDialog
UI.ConfirmImportBiS    = UI.ConfirmImport

-- ============================================================================
-- Export dialog — produces a copy-pasteable text block of the current
-- loadout's picks for the viewed phase. Round-trip parsing isn't supported
-- yet (defer to a future polish brief if/when the user asks).
-- ============================================================================

local exportDialog

local function BuildExportDialog(parent)
    local d = CreateFrame("Frame", "ItemTrackerGearGoalsExportDialog", parent)
    d:SetFrameStrata("DIALOG")
    d:SetSize(440, 420)
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

    d.hint = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.hint:SetPoint("TOP", d.title, "BOTTOM", 0, -4)
    d.hint:SetText("Press Ctrl+A then Ctrl+C to copy, or click the box first.")
    d.hint:SetTextColor(unpack(P.label))

    -- ScrollFrame + multi-line EditBox for read-mostly text the user
    -- highlights and copies out.
    local sf = CreateFrame("ScrollFrame", "ItemTrackerGearGoalsExportScroll",
        inner, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     16, -56)
    sf:SetPoint("BOTTOMRIGHT", -36, 56)
    AddBackground(sf, P.surfaceAlt)
    AddBorder(sf, P.border)

    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetWidth(380)
    eb:SetAutoFocus(false)
    eb:SetTextColor(unpack(P.value))
    eb:SetScript("OnEscapePressed", function() d:Hide() end)
    sf:SetScrollChild(eb)
    d.editBox = eb

    d.closeBtn = CreateFrame("Button", nil, inner)
    d.closeBtn:SetSize(110, 24)
    d.closeBtn:SetPoint("BOTTOM", 0, 10)
    AddBackground(d.closeBtn, P.surfaceAlt)
    AddBorder(d.closeBtn, P.border)
    d.closeBtn.text = d.closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.closeBtn.text:SetPoint("CENTER")
    d.closeBtn.text:SetText("Close")
    d.closeBtn.text:SetTextColor(unpack(P.value))
    d.closeBtn:SetScript("OnClick", function() d:Hide() end)
    return d
end

function UI:OpenExportDialog()
    if not exportDialog then exportDialog = BuildExportDialog(frame) end

    local GG          = IT.GearGoals
    local loadoutID   = viewLoadoutID or GG:GetMainLoadoutID()
    local phase       = GG:GetViewedPhase()
    local loadoutName = GG:GetLoadoutName(loadoutID)
    local phaseLabel  = GG.PHASE_LABEL[phase] or phase

    exportDialog.title:SetText("Export — " .. loadoutName .. " . " .. phaseLabel)

    local encoded = GG:EncodePhase(loadoutID, phase) or ""
    -- The encoded string is round-trippable via the Import dialog's
    -- "From paste" source. Keep it as a single line so users can copy
    -- without worrying about line breaks getting clipped.
    exportDialog.editBox:SetText(encoded)
    exportDialog.editBox:SetHeight(280)
    exportDialog.editBox:HighlightText()
    exportDialog:Show()
    exportDialog.editBox:SetFocus()
end

-- ============================================================================
-- RAIDS pane
-- Same scroll-frame layout as LOADOUT, but rendered as one card per raid
-- (parsed from the AtlasLoot source label) containing the picks that drop
-- there. Items without a known source go into "Unknown source".
-- ============================================================================

local function BuildRaidsPane(parent)
    local sf = CreateFrame("ScrollFrame", "ItemTrackerGearGoalsRaidsScroll",
        parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     parent.filterRow, "BOTTOMLEFT", 0, -8)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)
    sf:Hide()

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(W - SIDEBAR_W - 50, 1)
    sf:SetScrollChild(sc)
    sf.scrollChild = sc
    sf.cards       = {}    -- raidName -> card
    return sf
end

--- Resolve the raid bucket label for an itemID by walking AtlasLoot's
--- direct source first, then the token chain via Tokens. Falls back to
--- "Unknown source" so items always end up in *some* bucket.
RaidBucketFor = function(itemID)
    local AL = IT.GearGoalsAtlasLoot
    if not AL then return "Unknown source" end

    local function fromSrc(src)
        if not src then return nil end
        if type(src.raid) == "string" and src.raid ~= "" then return src.raid end
        if type(src.boss) == "string" and src.boss ~= "" then return src.boss end
        return nil
    end

    local raidName = AL.GetSource and fromSrc(AL:GetSource(itemID))
    if raidName then return raidName end

    local Tokens = IT.GearGoalsTokens
    if Tokens and Tokens.GetTokenFor then
        local tokenID = Tokens:GetTokenFor(itemID)
        if tokenID and AL.GetSource then
            raidName = fromSrc(AL:GetSource(tokenID))
            if raidName then return raidName end
        end
    end
    return "Unknown source"
end

function UI:RenderRaidsPane()
    local pane = frame.raidsPane
    if not pane then return end
    local GG    = IT.GearGoals
    local spec  = viewLoadoutID or GG:GetMainLoadoutID()
    local phase = GG:GetViewedPhase()

    -- Gather goals grouped by raid bucket (in load-order so cards stay
    -- stable across renders).
    local byRaid, raidOrder = {}, {}
    for _, slotID in ipairs(GG.SLOT_ORDER) do
        for _, g in ipairs(GG:GetGoals(spec, phase, slotID)) do
            local bucket = RaidBucketFor(g.itemID)
            if not byRaid[bucket] then
                byRaid[bucket] = {}
                table.insert(raidOrder, bucket)
            end
            table.insert(byRaid[bucket], { slotID = slotID, goal = g })
        end
    end
    table.sort(raidOrder, function(a, b)
        if a == "Unknown source" then return false end
        if b == "Unknown source" then return true end
        return a < b
    end)

    -- Hide every pre-existing card; we'll re-show only the ones we render.
    for _, c in pairs(pane.cards) do c:Hide() end

    local y = 0
    for _, raidName in ipairs(raidOrder) do
        local card = pane.cards[raidName]
        if not card then
            card = CreatePanel(pane.scrollChild, P.surface)
            AddBorder(card, P.border)
            local headerBg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
            headerBg:SetPoint("TOPLEFT")
            headerBg:SetPoint("TOPRIGHT")
            headerBg:SetHeight(SLOT_HEADER_H)
            SetColor(headerBg, P.surfaceAlt)
            card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            card.title:SetPoint("TOPLEFT", 12, -7)
            card.title:SetTextColor(unpack(P.value))
            card.count = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            card.count:SetPoint("TOPRIGHT", -12, -7)
            card.count:SetTextColor(unpack(P.label))
            card.rows = {}
            pane.cards[raidName] = card
        end

        local entries = byRaid[raidName]
        card.title:SetText(raidName)
        card.count:SetText(#entries .. (#entries == 1 and " pick" or " picks"))

        local rowsNeeded = #entries
        local cardH = SLOT_HEADER_H + 6 + rowsNeeded * (PICK_ROW_H + 4)
        card:SetHeight(cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT",  pane.scrollChild, "TOPLEFT",  4, -y)
        card:SetPoint("TOPRIGHT", pane.scrollChild, "TOPRIGHT", -4, -y)
        y = y + cardH + 8

        while #card.rows < rowsNeeded do
            table.insert(card.rows, MakePickRow(card, nil))   -- slotID set per render
        end
        for i, row in ipairs(card.rows) do
            if i <= rowsNeeded then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  card, "TOPLEFT",  6,
                    -(SLOT_HEADER_H + 4 + (i - 1) * (PICK_ROW_H + 4)))
                row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6,
                    -(SLOT_HEADER_H + 4 + (i - 1) * (PICK_ROW_H + 4)))
                row:SetHeight(PICK_ROW_H)
                local entry = entries[i]
                RenderRow(row, entry.slotID, entry.goal)   -- sets row.slotID
                row:Show()
            else
                row:Hide()
            end
        end
        card:Show()
    end

    pane.scrollChild:SetHeight(math.max(y + 8, pane:GetHeight()))
end

-- ============================================================================
-- LOOT LOG pane
-- Filters IT.LootHistory:GetAll() to entries that match a goal on any
-- loadout (direct or via token redemption). Each row: timestamp, item link,
-- looter name, plus a small "<loadout> P<N> rank #N" tag per match.
-- ============================================================================

local LOG_ROW_H = 40

local function BuildLootLogPane(parent)
    local sf = CreateFrame("ScrollFrame", "ItemTrackerGearGoalsLootLogScroll",
        parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     parent.filterRow, "BOTTOMLEFT", 0, -8)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)
    sf:Hide()

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(W - SIDEBAR_W - 50, 1)
    sf:SetScrollChild(sc)
    sf.scrollChild = sc
    sf.rows        = {}

    sf.empty = sf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sf.empty:SetPoint("CENTER")
    sf.empty:SetText("No tracked drops yet.")
    sf.empty:SetTextColor(unpack(P.label))
    sf.empty:Hide()
    return sf
end

local function MakeLogRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LOG_ROW_H)
    AddBackground(row, P.surfaceAlt)

    -- Top row: time (left), item name (middle, expanding), looter (right)
    row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.time:SetPoint("TOPLEFT", 8, -6)
    row.time:SetWidth(64)
    row.time:SetJustifyH("LEFT")
    row.time:SetTextColor(unpack(P.label))

    row.looter = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.looter:SetPoint("TOPRIGHT", -8, -6)
    row.looter:SetWidth(120)
    row.looter:SetJustifyH("RIGHT")
    row.looter:SetTextColor(unpack(P.label))

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT",  row.time,   "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.looter, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- Bottom row: tags spanning full width
    row.tags = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.tags:SetPoint("BOTTOMLEFT",  8, 6)
    row.tags:SetPoint("BOTTOMRIGHT", -8, 6)
    row.tags:SetJustifyH("LEFT")
    row.tags:SetWordWrap(false)
    row.tags:SetTextColor(unpack(P.label))

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.itemLink)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

function UI:RenderLootLogPane()
    local pane = frame.lootLogPane
    if not pane then return end
    local GG = IT.GearGoals
    local LH = IT.LootHistory

    local entries = (LH and LH.GetAll) and LH:GetAll() or {}
    local Tokens  = IT.GearGoalsTokens

    -- Build the list of matched (entry, matches) pairs in original order.
    local matched = {}
    for _, e in ipairs(entries) do
        if e.itemID then
            local list = GG:FindAllMatches(e.itemID)
            if Tokens and Tokens:IsToken(e.itemID) then
                for _, m in ipairs(GG:FindAllMatchesForToken(e.itemID)) do
                    table.insert(list, m)
                end
            end
            if #list > 0 then
                table.insert(matched, { entry = e, matches = list })
            end
        end
    end

    if #matched == 0 then
        pane.empty:Show()
        for _, r in ipairs(pane.rows) do r:Hide() end
        pane.scrollChild:SetHeight(pane:GetHeight())
        return
    end
    pane.empty:Hide()

    -- Render rows top-down
    while #pane.rows < #matched do
        table.insert(pane.rows, MakeLogRow(pane.scrollChild))
    end

    for i, row in ipairs(pane.rows) do
        if i <= #matched then
            local pair  = matched[i]
            local entry = pair.entry
            local _, _, quality = GetItemInfo(entry.itemID)
            local r, g, b = IT:GetQualityColor(quality or entry.quality or 1)

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  pane.scrollChild, "TOPLEFT",  4, -((i - 1) * (LOG_ROW_H + 4)))
            row:SetPoint("TOPRIGHT", pane.scrollChild, "TOPRIGHT", -4, -((i - 1) * (LOG_ROW_H + 4)))

            row.itemLink = entry.itemLink
            row.time:SetText(IT:FormatTimeAgo(entry.timestamp))
            row.name:SetText(entry.itemLink or ("Item " .. entry.itemID))
            row.name:SetTextColor(r, g, b)
            row.looter:SetText(entry.player or "—")

            -- Match tags: "<loadoutName> P<N> rank #N", joined by " · "
            local tagBits = {}
            for _, m in ipairs(pair.matches) do
                local lname = GG:GetLoadoutName(m.specKey) or m.specKey
                local plabel = GG.PHASE_LABEL[m.phase] or m.phase
                table.insert(tagBits, lname .. " " .. plabel .. " #" .. m.rank)
            end
            row.tags:SetText(table.concat(tagBits, " · "))
            row:Show()
        else
            row:Hide()
        end
    end

    pane.scrollChild:SetHeight(math.max(#matched * (LOG_ROW_H + 4) + 8, pane:GetHeight()))
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
    frame.tabStrip = BuildTopTabs(frame, frame.header)
    frame.phaseBar = BuildPhaseBar(frame, frame.tabStrip)

    -- Sidebar (left) and main pane (right)
    sidebar = BuildSidebar(frame, frame.phaseBar)

    frame.filterRow = BuildFilterRow(frame)
    -- Sidebar's TOPRIGHT is already 8px below the phase bar (via sidebar's
    -- TOPLEFT anchor), so anchoring filterRow to that gives the right y.
    frame.filterRow:SetPoint("TOPLEFT",  sidebar, "TOPRIGHT", 8, 0)
    frame.filterRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, 0)

    -- LOADOUT pane: the existing scrollFrame + slot cards. The same area
    -- below the filter row is reused by the RAIDS and LOOT LOG panes via
    -- show/hide in Refresh.
    scrollFrame = CreateFrame("ScrollFrame", "ItemTrackerGearGoalsScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     frame.filterRow, "BOTTOMLEFT", 0, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(W - SIDEBAR_W - 50, 1)
    scrollFrame:SetScrollChild(scrollChild)

    for _, slotID in ipairs(IT.GearGoals.SLOT_ORDER) do
        slotCards[slotID] = MakeSlotCard(scrollChild, slotID)
    end
    frame.loadoutPane = scrollFrame
    frame.raidsPane   = BuildRaidsPane(frame)
    frame.lootLogPane = BuildLootLogPane(frame)

    -- React to data changes
    IT.Events:Subscribe("GEAR_GOAL_LIST_CHANGED",     function() UI:Refresh() end)
    IT.Events:Subscribe("GEAR_GOALS_PHASE_CHANGED",   function() UI:Refresh() end)
    IT.Events:Subscribe("GEAR_GOALS_LOADOUT_CHANGED", function() UI:Refresh() end)
    if IT.LootHistory then
        IT.Events:Subscribe("HISTORY_UPDATED", function()
            if activeTab == "LOOT LOG" then UI:Refresh() end
        end)
    end
end

function UI:Initialize()
    -- Lazy-build on first show; nothing to do at addon load.
    IT:Debug("GearGoalsUI initialized")
end
