--[[
    ItemTracker - GearGoalsAlert Module
    Single Responsibility: Render the centered drop-alert popup when a goal
    item drops. Subscribes to GEAR_GOAL_DROPPED.

    Visual style: dark (near-black) surface with gold accents and a subtle
    purple glow. Mirrors the user-supplied design — distinct from ItemTracker's
    cyan/glassy palette.

    Buttons:
        Item is on main spec list             -> "ROLL 100 · MS"
        Item is on off  spec list             -> "ROLL 99  · OS"
        Item is on both                       -> both buttons side by side
    Issues /roll via RandomRoll. No automatic action.
]]

local _, IT = ...
local Alert = {}
IT.GearGoalsAlert = Alert

-- ============================================================================
-- Design palette (GearGoals — dark/gold/purple per user's design)
-- ============================================================================

local P = {
    bg          = { 0.04, 0.04, 0.06, 0.97 },
    surface     = { 0.07, 0.07, 0.10, 1.00 },
    border      = { 0.55, 0.43, 0.18, 0.80 },   -- gold border
    borderDim   = { 0.18, 0.18, 0.23, 0.80 },
    accent      = { 1.00, 0.78, 0.20 },         -- gold (primary)
    accentDim   = { 0.55, 0.43, 0.18 },
    label       = { 0.45, 0.45, 0.52 },
    value       = { 0.85, 0.85, 0.90 },
    purple      = { 0.64, 0.21, 0.93 },
    btnBg       = { 0.10, 0.10, 0.14, 1.0 },
}

local POPUP_WIDTH  = 460
local POPUP_HEIGHT = 360

-- ============================================================================
-- State
-- ============================================================================

local frame
local currentDrop  -- last GEAR_GOAL_DROPPED payload

-- ============================================================================
-- Helpers
-- ============================================================================

local function SetColor(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

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

local function AddCornerBracket(parent, corner, c, length)
    length = length or 12
    local t1 = parent:CreateTexture(nil, "OVERLAY")
    local t2 = parent:CreateTexture(nil, "OVERLAY")
    SetColor(t1, c); SetColor(t2, c)
    if corner == "TOPLEFT" then
        t1:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); t1:SetSize(length, 1)
        t2:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0); t2:SetSize(1, length)
    elseif corner == "TOPRIGHT" then
        t1:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0); t1:SetSize(length, 1)
        t2:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0); t2:SetSize(1, length)
    elseif corner == "BOTTOMLEFT" then
        t1:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0); t1:SetSize(length, 1)
        t2:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0); t2:SetSize(1, length)
    elseif corner == "BOTTOMRIGHT" then
        t1:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0); t1:SetSize(length, 1)
        t2:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0); t2:SetSize(1, length)
    end
end

local function GoldText(s) return "|cFFFFCC33" .. s .. "|r" end
local function DimText(s)  return "|cFF6E6E78" .. s .. "|r" end

-- ============================================================================
-- Button factory (gold primary, dark secondary)
-- ============================================================================

local function MakeButton(parent, label, isPrimary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(150, 32)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, isPrimary and P.accentDim or P.btnBg)
    b.bg = bg

    AddBorder(b, isPrimary and P.accent or P.borderDim)

    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("CENTER")
    b.label:SetText(label)
    b.label:SetTextColor(unpack(isPrimary and P.accent or P.value))

    b:SetScript("OnEnter", function(self)
        SetColor(bg, isPrimary and P.accent or { 0.18, 0.18, 0.22, 1 })
        if isPrimary then self.label:SetTextColor(0.05, 0.05, 0.05) end
    end)
    b:SetScript("OnLeave", function(self)
        SetColor(bg, isPrimary and P.accentDim or P.btnBg)
        self.label:SetTextColor(unpack(isPrimary and P.accent or P.value))
    end)

    return b
end

-- ============================================================================
-- Frame construction (lazy)
-- ============================================================================

local function BuildFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "ItemTrackerGearGoalsAlert", UIParent)
    frame:SetSize(POPUP_WIDTH, POPUP_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(200)
    frame:Hide()

    -- Position from saved anchor or center
    local anchor = IT.db.settings.gearGoals and IT.db.settings.gearGoals.popupAnchor
    if anchor and anchor.point then
        frame:SetPoint(anchor.point, UIParent, anchor.relativePoint or anchor.point, anchor.x or 0, anchor.y or 0)
    else
        frame:SetPoint("CENTER")
    end

    -- Movable (drag from anywhere on the frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        IT.db.settings.gearGoals.popupAnchor = {
            point = point, relativePoint = relPoint, x = x, y = y,
        }
    end)
    frame:SetClampedToScreen(true)

    -- Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetColor(bg, P.bg)

    -- Inner surface (slightly inset)
    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT",     12, -12)
    inner:SetPoint("BOTTOMRIGHT", -12, 12)
    local innerBg = inner:CreateTexture(nil, "BACKGROUND")
    innerBg:SetAllPoints()
    SetColor(innerBg, P.surface)
    AddBorder(inner, P.border)

    -- Corner brackets (decorative)
    AddCornerBracket(inner, "TOPLEFT",     P.accent, 18)
    AddCornerBracket(inner, "TOPRIGHT",    P.accent, 18)
    AddCornerBracket(inner, "BOTTOMLEFT",  P.accent, 18)
    AddCornerBracket(inner, "BOTTOMRIGHT", P.accent, 18)

    -- ESC handler: register as a UI panel that closes on ESC
    table.insert(UISpecialFrames, "ItemTrackerGearGoalsAlert")

    -- Header line: "· PHASE 3 · PICK #1 FROM YOUR LIST ·"
    frame.headerLine = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.headerLine:SetPoint("TOP", 0, -22)
    frame.headerLine:SetTextColor(unpack(P.accent))

    -- Big title
    frame.title = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.title:SetPoint("TOP", frame.headerLine, "BOTTOM", 0, -8)
    frame.title:SetText("IT HAS BEGUN")
    frame.title:SetTextColor(unpack(P.accent))

    -- Item icon (with rank corner badge)
    frame.icon = inner:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(64, 64)
    frame.icon:SetPoint("TOP", frame.title, "BOTTOM", 0, -12)
    frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    frame.iconFrame = CreateFrame("Frame", nil, inner)
    frame.iconFrame:SetSize(72, 72)
    frame.iconFrame:SetPoint("CENTER", frame.icon)
    AddBorder(frame.iconFrame, { P.purple[1], P.purple[2], P.purple[3], 0.9 })

    frame.rankBadge = CreateFrame("Frame", nil, inner)
    frame.rankBadge:SetSize(28, 22)
    frame.rankBadge:SetPoint("TOPRIGHT", frame.iconFrame, "TOPRIGHT", 6, 6)
    local rb = frame.rankBadge:CreateTexture(nil, "BACKGROUND")
    rb:SetAllPoints()
    SetColor(rb, P.accentDim)
    AddBorder(frame.rankBadge, P.accent)
    frame.rankBadgeText = frame.rankBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.rankBadgeText:SetPoint("CENTER")
    frame.rankBadgeText:SetTextColor(unpack(P.accent))

    -- Item name + subtitle
    frame.itemName = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.itemName:SetPoint("TOP", frame.iconFrame, "BOTTOM", 0, -10)

    frame.subtitle = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.subtitle:SetPoint("TOP", frame.itemName, "BOTTOM", 0, -2)
    frame.subtitle:SetTextColor(unpack(P.label))

    -- Redeem list — when the drop is a token, list each wishlist item the
    -- token matches. Hidden entirely when there are no token matches.
    frame.redeemHeader = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.redeemHeader:SetPoint("TOP", frame.subtitle, "BOTTOM", 0, -10)
    frame.redeemHeader:SetText("|cFFFFCC33REDEEMS FOR|r")
    frame.redeemHeader:Hide()

    -- Pool of FontStrings reused across drops. Created on demand in Show().
    frame.redeemLines = {}

    -- Three meta cells: PHASE / PICK / LOOTED BY
    local function MakeMeta(parent, anchor, anchorTo, anchorAt, x, y)
        local cell = CreateFrame("Frame", nil, parent)
        cell:SetSize(120, 40)
        cell:SetPoint(anchor, anchorTo, anchorAt or anchor, x or 0, y or 0)
        local lab = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lab:SetPoint("TOP", 0, -2)
        lab:SetTextColor(unpack(P.label))
        local val = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        val:SetPoint("TOP", lab, "BOTTOM", 0, -4)
        val:SetTextColor(unpack(P.accent))
        cell.label = lab; cell.value = val
        return cell
    end

    local metaRow = CreateFrame("Frame", nil, inner)
    metaRow:SetSize(POPUP_WIDTH - 80, 50)
    -- Anchored dynamically in Show(): below redeem list when present, else
    -- below subtitle. Keep an initial anchor so the layout passes if Show
    -- happens to set zero redeem lines.
    metaRow:SetPoint("TOP", frame.subtitle, "BOTTOM", 0, -16)
    frame.metaRow = metaRow
    frame.metaPhase  = MakeMeta(metaRow, "LEFT",   metaRow, "LEFT",  20, 0)
    frame.metaPhase.label:SetText("PHASE")
    frame.metaPick   = MakeMeta(metaRow, "CENTER", metaRow, "CENTER", 0, 0)
    frame.metaPick.label:SetText("PICK")
    frame.metaLooted = MakeMeta(metaRow, "RIGHT",  metaRow, "RIGHT", -20, 0)
    frame.metaLooted.label:SetText("LOOTED BY")

    -- Action row: up to two buttons (MS / OS), centered
    frame.actionRow = CreateFrame("Frame", nil, inner)
    frame.actionRow:SetSize(POPUP_WIDTH - 40, 40)
    frame.actionRow:SetPoint("BOTTOM", 0, 36)

    frame.btnMS = MakeButton(frame.actionRow, "ROLL 100 · MS", true)
    frame.btnMS:SetScript("OnClick", function() Alert:DoRoll(100); Alert:Hide() end)

    frame.btnOS = MakeButton(frame.actionRow, "ROLL 99 · OS", true)
    frame.btnOS:SetScript("OnClick", function() Alert:DoRoll(99); Alert:Hide() end)

    frame.btnDismiss = MakeButton(frame.actionRow, "DISMISS", false)
    frame.btnDismiss:SetScript("OnClick", function() Alert:Hide() end)

    -- Footer hint
    frame.footer = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.footer:SetPoint("BOTTOM", 0, 12)
    -- Decimal escape: ↵ U+21B5 (Lua 5.1 doesn't support \xNN hex escapes)
    frame.footer:SetText(DimText("\226\134\181 Enter · Esc to dismiss"))

    -- Enter triggers MS roll if visible, else OS, else dismiss
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ENTER" or key == "KP_ENTER" then
            self:SetPropagateKeyboardInput(false)
            if frame.btnMS:IsShown() then
                Alert:DoRoll(100)
            elseif frame.btnOS:IsShown() then
                Alert:DoRoll(99)
            end
            Alert:Hide()
        elseif key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            Alert:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return frame
end

-- ============================================================================
-- Layout the action row given which buttons are shown
-- ============================================================================

local function LayoutActions(showMS, showOS)
    local row = frame.actionRow
    frame.btnMS:Hide()
    frame.btnOS:Hide()
    frame.btnDismiss:ClearAllPoints()
    frame.btnMS:ClearAllPoints()
    frame.btnOS:ClearAllPoints()

    if showMS and showOS then
        frame.btnMS:SetPoint("CENTER", row, "CENTER", -82, 0); frame.btnMS:Show()
        frame.btnOS:SetPoint("CENTER", row, "CENTER",  82, 0); frame.btnOS:Show()
        frame.btnDismiss:SetPoint("LEFT", row, "LEFT", 0, 0); frame.btnDismiss:Hide()
    elseif showMS then
        frame.btnMS:SetPoint("CENTER", row, "CENTER", -82, 0); frame.btnMS:Show()
        frame.btnDismiss:SetPoint("CENTER", row, "CENTER", 82, 0); frame.btnDismiss:Show()
    elseif showOS then
        frame.btnOS:SetPoint("CENTER", row, "CENTER", -82, 0); frame.btnOS:Show()
        frame.btnDismiss:SetPoint("CENTER", row, "CENTER", 82, 0); frame.btnDismiss:Show()
    else
        frame.btnDismiss:SetPoint("CENTER"); frame.btnDismiss:Show()
    end
end

-- ============================================================================
-- Roll
-- ============================================================================

function Alert:DoRoll(max)
    -- /roll N rolls between 1 and N. RandomRoll is (low, high), so /roll 100
    -- maps to RandomRoll(1, 100), not RandomRoll(100, 100).
    if RandomRoll then
        RandomRoll(1, max)
    else
        IT:Print("RandomRoll API unavailable — type /roll " .. max .. " manually.", IT.Colors.warning)
    end
end

-- ============================================================================
-- Show / Hide
-- ============================================================================

function Alert:Show(drop)
    BuildFrame()
    currentDrop = drop

    local GG = IT.GearGoals
    local matches = drop.matches or {}
    if #matches == 0 then return end

    -- Pick a "primary" match for headline data: prefer main spec, then lowest rank
    table.sort(matches, function(a, b)
        if a.isMainSpec ~= b.isMainSpec then return a.isMainSpec end
        return a.rank < b.rank
    end)
    local primary = matches[1]

    -- Item info — for token drops, use the *token's* visual but add a
    -- "Redeems for: <goal>" line so the user knows why this matched their list.
    local dropName, _, dropQuality, _, _, _, _, _, _, dropIcon = GetItemInfo(drop.itemLink or drop.itemID)
    if not dropName then dropName = "Item " .. tostring(drop.itemID) end
    local r, g, b = IT:GetQualityColor(dropQuality or 4)

    frame.icon:SetTexture(dropIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.itemName:SetText(dropName)
    frame.itemName:SetTextColor(r, g, b)
    frame.rankBadgeText:SetText("#" .. primary.rank)

    -- Subtitle: Slot · ilvl · Boss
    local slotLabel = (GG and GG:GetSlotLabel(primary.slotID)) or ""
    local _, _, _, ilvl = GetItemInfo(drop.itemID)
    local sourceLabel = (IT.GearGoalsAtlasLoot and IT.GearGoalsAtlasLoot:GetSourceLabel(drop.itemID)) or ""
    local subtitleParts = {}
    if slotLabel ~= "" then table.insert(subtitleParts, slotLabel) end
    if ilvl then          table.insert(subtitleParts, "ilvl " .. ilvl) end
    if sourceLabel ~= "" then table.insert(subtitleParts, sourceLabel) end
    frame.subtitle:SetText(table.concat(subtitleParts, " · "))

    -- Redeem list: collect unique goal items reached via token redemption.
    -- Each line: <quality-coloured goal name>  ·  <SpecLabel> · rank #N
    local redeems = {}
    local redeemSeen = {}
    for _, m in ipairs(matches) do
        if m.isToken and m.goalItemID and m.goalItemID ~= drop.itemID then
            local key = m.goalItemID .. "|" .. m.specKey
            if not redeemSeen[key] then
                redeemSeen[key] = true
                table.insert(redeems, m)
            end
        end
    end

    -- Hide pooled lines first; show + populate as needed.
    for _, line in ipairs(frame.redeemLines) do line:Hide() end

    local lineHeight = 14
    local listExtraH = 0
    if #redeems > 0 then
        frame.redeemHeader:Show()
        for i, m in ipairs(redeems) do
            local line = frame.redeemLines[i]
            if not line then
                line = frame.redeemHeader:GetParent():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                frame.redeemLines[i] = line
            end
            line:ClearAllPoints()
            line:SetPoint("TOP", i == 1 and frame.redeemHeader or frame.redeemLines[i - 1],
                                  "BOTTOM", 0, -2)
            local goalName = GetItemInfo(m.goalItemID) or ("Item " .. m.goalItemID)
            local _, _, q = GetItemInfo(m.goalItemID)
            local rr, gg, bb = IT:GetQualityColor(q or 4)
            local hex = string.format("|cFF%02X%02X%02X", rr * 255, gg * 255, bb * 255)
            local loadoutName = GG:GetLoadoutName(m.specKey)
            line:SetText(string.format("%s%s|r  |cFF888892·  %s · rank #%d|r",
                hex, goalName, loadoutName, m.rank))
            line:Show()
        end
        listExtraH = 14 + (#redeems * lineHeight)   -- header + lines

        frame.metaRow:ClearAllPoints()
        frame.metaRow:SetPoint("TOP", frame.redeemLines[#redeems], "BOTTOM", 0, -10)
    else
        frame.redeemHeader:Hide()
        frame.metaRow:ClearAllPoints()
        frame.metaRow:SetPoint("TOP", frame.subtitle, "BOTTOM", 0, -16)
    end

    -- Grow popup vertically when the redeem list pushes meta+buttons down
    frame:SetHeight(POPUP_HEIGHT + listExtraH)

    -- Header line
    local phaseLabel = (GG and GG.PHASE_LABEL[primary.phase]) or primary.phase
    frame.headerLine:SetText("· " .. phaseLabel .. " · PICK #" .. primary.rank .. " FROM YOUR LIST ·")

    -- Meta cells
    frame.metaPhase.value:SetText(phaseLabel)
    frame.metaPick.value:SetText("#" .. primary.rank .. " of " .. #(GG:GetGoals(primary.specKey, primary.phase, primary.slotID)))
    frame.metaLooted.value:SetText(drop.looter or (drop.fromChat and "Chat" or "?"))

    -- Decide which roll buttons to show
    local hasMS, hasOS = false, false
    for _, m in ipairs(matches) do
        if m.isMainSpec then hasMS = true else hasOS = true end
    end
    LayoutActions(hasMS, hasOS)

    if not frame:IsShown() then
        frame:Show()
        if PlaySound and IT.db.settings.gearGoals.notifySound then
            PlaySound(SOUNDKIT.RAID_WARNING or 8959)
        end
    end
end

function Alert:Hide()
    if frame and frame:IsShown() then frame:Hide() end
    currentDrop = nil
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Alert:Initialize()
    IT.Events:Subscribe("GEAR_GOAL_DROPPED", function(drop) Alert:Show(drop) end)
    IT:Debug("GearGoalsAlert initialized")
end
