--[[
    ItemTracker - Config Module
    Single Responsibility: Settings persistence, settings UI panel,
    and Blizzard Interface Options integration.

    Registers with InterfaceOptions_AddCategory so the addon appears
    in Escape → Interface → AddOns (Curseforge-compatible pattern).
]]

local _, IT = ...
local Config = {}
IT.Config = Config

-- ============================================================================
-- Color Definitions (shared glassy palette)
-- ============================================================================

local CD = {
    bg      = { 0.04, 0.04, 0.06 },  bgA  = 0.93,
    border  = { 0.18, 0.18, 0.23 },  borA = 0.80,
    divider = { 0.14, 0.14, 0.18 },  divA = 0.90,
    accent  = { 0.28, 0.74, 0.97 },
    label   = { 0.40, 0.40, 0.45 },
    value   = { 0.82, 0.84, 0.88 },
    barBg   = { 0.07, 0.07, 0.09 },
}

-- ============================================================================
-- Layout Constants
-- ============================================================================

local PANEL_WIDTH  = 340
local PANEL_HEIGHT = 502
local PADDING      = 16
local CONTENT_W    = PANEL_WIDTH - PADDING * 2

-- ============================================================================
-- Quality Dropdown Data
-- ============================================================================

local QUALITY_OPTIONS = {
    { value = 0, label = "|cFF9D9D9DPoor|r" },
    { value = 1, label = "|cFFFFFFFFCommon|r" },
    { value = 2, label = "|cFF1EFF00Uncommon|r" },
    { value = 3, label = "|cFF0070DDRare|r" },
    { value = 4, label = "|cFFA335EEEpic|r" },
    { value = 5, label = "|cFFFF8000Legendary|r" },
}

-- ============================================================================
-- State
-- ============================================================================

local configFrame
local blizzardPanel

-- ============================================================================
-- Helpers
-- ============================================================================

--- Draw a 1px border around any frame using 4 edge textures.
local function AddThinBorder(f, r, g, b, a)
    local t  = f:CreateTexture(nil, "OVERLAY")
    t:SetPoint("TOPLEFT");     t:SetPoint("TOPRIGHT");     t:SetHeight(1); t:SetColorTexture(r, g, b, a)
    local bb = f:CreateTexture(nil, "OVERLAY")
    bb:SetPoint("BOTTOMLEFT"); bb:SetPoint("BOTTOMRIGHT"); bb:SetHeight(1); bb:SetColorTexture(r, g, b, a)
    local l  = f:CreateTexture(nil, "OVERLAY")
    l:SetPoint("TOPLEFT");     l:SetPoint("BOTTOMLEFT");   l:SetWidth(1);  l:SetColorTexture(r, g, b, a)
    local rr = f:CreateTexture(nil, "OVERLAY")
    rr:SetPoint("TOPRIGHT");   rr:SetPoint("BOTTOMRIGHT");  rr:SetWidth(1); rr:SetColorTexture(r, g, b, a)
end

-- ============================================================================
-- Section Header
-- ============================================================================

local function CreateSectionHeader(parent, text, yOffset)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)
    lbl:SetText(text)
    lbl:SetTextColor(CD.accent[1], CD.accent[2], CD.accent[3])

    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  PADDING, yOffset - 14)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING, yOffset - 14)
    line:SetColorTexture(CD.divider[1], CD.divider[2], CD.divider[3], CD.divA)

    return yOffset - 22
end

-- ============================================================================
-- Checkbox
-- ============================================================================

local function CreateCheckbox(parent, label, yOffset, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(CONTENT_W, 18)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)

    -- 14×14 box with thin border
    local box = CreateFrame("Button", nil, container)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", container, "LEFT", 0, 0)

    local boxBg = box:CreateTexture(nil, "BACKGROUND")
    boxBg:SetAllPoints()
    boxBg:SetColorTexture(CD.barBg[1], CD.barBg[2], CD.barBg[3], 1)

    AddThinBorder(box, CD.border[1], CD.border[2], CD.border[3], 0.85)

    -- Accent fill when checked
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(CD.accent[1], CD.accent[2], CD.accent[3], 1)
    fill:Hide()

    box:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    box:GetHighlightTexture():SetBlendMode("ADD")

    -- Label
    local txt = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("LEFT", box, "RIGHT", 8, 0)
    txt:SetText(label)
    txt:SetTextColor(CD.value[1], CD.value[2], CD.value[3])

    -- State
    local isChecked = false
    local function setChecked(val)
        isChecked = not not val
        if isChecked then fill:Show() else fill:Hide() end
    end

    box:SetScript("OnClick", function()
        setChecked(not isChecked)
        setValue(isChecked)
    end)

    container:SetScript("OnShow", function()
        if getValue then setChecked(getValue()) end
    end)

    return container
end

-- ============================================================================
-- Generic Dropdown
-- ============================================================================

local function CreateDropdown(parent, label, yOffset, options, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(CONTENT_W, 38)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    lbl:SetText(label)
    lbl:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    -- Button that shows current selection
    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(160, 20)
    btn:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(CD.barBg[1], CD.barBg[2], CD.barBg[3], 1)

    AddThinBorder(btn, CD.border[1], CD.border[2], CD.border[3], 0.85)

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.label:SetJustifyH("LEFT")

    -- Small triangle drawn with a texture (avoid Unicode issues)
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(8, 6)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    arrow:SetColorTexture(CD.label[1], CD.label[2], CD.label[3], 1)

    -- Dropdown menu
    local menu = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    menu:SetSize(160, #options * 20 + 4)
    menu:SetPoint("TOP", btn, "BOTTOM", 0, 1)  -- overlap 1px so mouse doesn't leave a gap
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    menu:SetBackdropColor(CD.bg[1], CD.bg[2], CD.bg[3], 0.96)
    menu:SetBackdropBorderColor(CD.border[1], CD.border[2], CD.border[3], CD.borA)
    menu:Hide()

    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, menu)
        item:SetSize(156, 20)
        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -(i - 1) * 20 - 2)

        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
        item.text:SetText(opt.label)

        local hl = item:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(CD.accent[1], CD.accent[2], CD.accent[3], 0.15)

        item:SetScript("OnClick", function()
            setValue(opt.value)
            btn.label:SetText(opt.label)
            menu:Hide()
        end)
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)

    -- Auto-close when mouse leaves both button and menu (with grace period)
    menu:SetScript("OnShow", function(self)
        local grace = 0.3  -- seconds before auto-close starts checking
        self:SetScript("OnUpdate", function(_, dt)
            if grace > 0 then
                grace = grace - dt
                return
            end
            if not btn:IsMouseOver() and not self:IsMouseOver() then
                self:Hide()
            end
        end)
    end)
    menu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

    -- Refresh value on show
    container:SetScript("OnShow", function()
        local val = getValue()
        for _, opt in ipairs(options) do
            if opt.value == val then
                btn.label:SetText(opt.label)
                break
            end
        end
    end)

    return container
end

-- ============================================================================
-- Slider (FishingKit pattern: thin custom track + invisible native Slider)
-- ============================================================================

local function CreateSlider(parent, label, yOffset, minVal, maxVal, step, getValue, setValue)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(CONTENT_W, 38)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)

    -- Label (left)
    local txt = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    txt:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    -- Value readout (right)
    local valTxt = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valTxt:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    valTxt:SetJustifyH("RIGHT")
    valTxt:SetTextColor(CD.value[1], CD.value[2], CD.value[3])

    -- Track background (thin, full width)
    local trackBg = container:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("TOPLEFT",  txt, "BOTTOMLEFT",  0, -8)
    trackBg:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -8)
    trackBg:SetHeight(4)
    trackBg:SetColorTexture(CD.barBg[1], CD.barBg[2], CD.barBg[3], 1)

    -- Accent fill (grows from left to current value)
    local trackFill = container:CreateTexture(nil, "ARTWORK")
    trackFill:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 0, 0)
    trackFill:SetHeight(4)
    trackFill:SetWidth(1)
    trackFill:SetColorTexture(CD.accent[1], CD.accent[2], CD.accent[3], 1)

    -- Thumb (small vertical bar)
    local thumb = container:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(3, 10)
    thumb:SetColorTexture(CD.value[1], CD.value[2], CD.value[3], 0.9)
    thumb:SetPoint("LEFT", trackBg, "LEFT", 0, 0)

    -- Manual mouse input on the track (native Slider unreliable in TBC Classic)
    local hitArea = CreateFrame("Frame", nil, container)
    hitArea:SetPoint("TOPLEFT",     trackBg, "TOPLEFT",     0,  8)
    hitArea:SetPoint("BOTTOMRIGHT", trackBg, "BOTTOMRIGHT", 0, -8)
    hitArea:EnableMouse(true)

    local currentValue = minVal

    local function updateVisuals(value)
        currentValue = value
        if step >= 1 then
            valTxt:SetText(tostring(math.floor(value + 0.5)))
        else
            valTxt:SetText(string.format("%.1f", value))
        end
        local w = trackBg:GetWidth()
        if w and w > 1 then
            local pct = (value - minVal) / math.max(1, maxVal - minVal)
            local fw = math.max(1, w * pct)
            trackFill:SetWidth(fw)
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", trackBg, "LEFT", math.max(0, fw - 1), 0)
        end
    end

    local function valueFromMouse()
        local cx = GetCursorPosition()
        local scale = trackBg:GetEffectiveScale()
        cx = cx / scale
        local left = trackBg:GetLeft()
        local right = trackBg:GetRight()
        if not left or not right or right <= left then return currentValue end
        local pct = math.max(0, math.min(1, (cx - left) / (right - left)))
        local raw = minVal + pct * (maxVal - minVal)
        return math.floor(raw / step + 0.5) * step
    end

    local isDragging = false

    hitArea:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then
            isDragging = true
            local v = valueFromMouse()
            updateVisuals(v)
            if setValue then setValue(v) end
        end
    end)
    hitArea:SetScript("OnMouseUp", function()
        isDragging = false
    end)
    hitArea:SetScript("OnUpdate", function()
        if isDragging then
            local v = valueFromMouse()
            if v ~= currentValue then
                updateVisuals(v)
                if setValue then setValue(v) end
            end
        end
    end)

    container:SetScript("OnShow", function()
        if getValue then
            updateVisuals(getValue())
        end
    end)

    return container
end

-- ============================================================================
-- Standalone Config Window
-- ============================================================================

local function CreateConfigFrame()
    local f = CreateFrame("Frame", "ItemTrackerConfig", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(CD.bg[1], CD.bg[2], CD.bg[3], CD.bgA)
    f:SetBackdropBorderColor(CD.border[1], CD.border[2], CD.border[3], CD.borA)

    -- Draggable
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, -12)
    title:SetText("|cFF00D1FFItemTracker Settings|r")

    -- Close button (× character)
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("|cFFAAAAAA\195\151|r")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self.text:SetText("|cFFFFFFFF\195\151|r") end)
    closeBtn:SetScript("OnLeave", function(self) self.text:SetText("|cFFAAAAAA\195\151|r") end)

    -- ── General ──
    local y = -36
    y = CreateSectionHeader(f, "General", y)

    CreateCheckbox(f, "Enable ItemTracker", y,
        function() return IT.db.settings.enabled end,
        function(v) IT.db.settings.enabled = v end)
    y = y - 22

    CreateCheckbox(f, "Lock bar position (hides bar)", y,
        function() return IT.db.settings.locked end,
        function(v)
            IT.db.settings.locked = v
            if IT.UI and IT.UI.UpdateLockState then IT.UI:UpdateLockState() end
        end)
    y = y - 22

    local DIRECTION_OPTIONS = {
        { value = true,  label = "Upward" },
        { value = false, label = "Downward" },
    }
    CreateDropdown(f, "Toast direction", y, DIRECTION_OPTIONS,
        function() return IT.db.settings.toastUpward end,
        function(v)
            IT.db.settings.toastUpward = v
            if IT.Toast and IT.Toast.RepositionAll then IT.Toast:RepositionAll() end
        end)
    y = y - 44

    CreateCheckbox(f, "Show gold loot toasts", y,
        function() return IT.db.settings.toastGold end,
        function(v) IT.db.settings.toastGold = v end)
    y = y - 22

    CreateCheckbox(f, "Show chat messages", y,
        function() return IT.db.settings.chatOutput end,
        function(v) IT.db.settings.chatOutput = v end)
    y = y - 22

    CreateCheckbox(f, "Show minimap button", y,
        function() return IT.db.settings.showMinimap end,
        function(v)
            IT.db.settings.showMinimap = v
            if IT.Minimap then IT.Minimap:UpdateVisibility() end
        end)
    y = y - 28

    -- ── Quality Thresholds ──
    y = CreateSectionHeader(f, "Quality Thresholds", y)

    CreateDropdown(f, "Solo loot \226\128\148 minimum quality", y, QUALITY_OPTIONS,
        function() return IT.db.settings.soloQualityThreshold end,
        function(v) IT.db.settings.soloQualityThreshold = v end)
    y = y - 44

    CreateDropdown(f, "Group / Raid loot \226\128\148 minimum quality", y, QUALITY_OPTIONS,
        function() return IT.db.settings.groupQualityThreshold end,
        function(v) IT.db.settings.groupQualityThreshold = v end)
    y = y - 48

    -- ── Toast ──
    y = CreateSectionHeader(f, "Toast Notifications", y)

    CreateSlider(f, "Toast duration (seconds)", y, 3, 30, 1,
        function() return IT.db.settings.toastDuration end,
        function(v) IT.db.settings.toastDuration = v end)
    y = y - 44

    CreateSlider(f, "Max visible toasts", y, 1, 10, 1,
        function() return IT.db.settings.toastMaxVisible end,
        function(v) IT.db.settings.toastMaxVisible = v end)
    y = y - 48

    -- ── History ──
    y = CreateSectionHeader(f, "History", y)

    CreateSlider(f, "History size (max entries)", y, 10, 500, 10,
        function() return IT.db.settings.historySize end,
        function(v) IT.db.settings.historySize = v end)

    -- ESC to close
    table.insert(UISpecialFrames, "ItemTrackerConfig")

    f:Hide()
    return f
end

-- ============================================================================
-- Blizzard Interface Options Panel
-- ============================================================================

local function CreateBlizzardPanel()
    if not InterfaceOptions_AddCategory then return nil end

    local panel = CreateFrame("Frame")
    panel.name = "ItemTracker"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFF00D1FFItemTracker|r")

    local version = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    version:SetText("Version " .. IT.VERSION .. " \226\128\148 " .. IT.BUILD)
    version:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -12)
    desc:SetText("Loot tracking and toast notifications for TBC Anniversary.")
    desc:SetTextColor(CD.value[1], CD.value[2], CD.value[3])

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(180, 26)
    openBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    openBtn:SetText("Open ItemTracker Settings")
    openBtn:SetScript("OnClick", function()
        if configFrame then configFrame:Show() end
    end)

    InterfaceOptions_AddCategory(panel)
    return panel
end

-- ============================================================================
-- Public API
-- ============================================================================

function Config:Toggle()
    if not configFrame then return end
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end

function Config:Show()
    if configFrame then configFrame:Show() end
end

function Config:Hide()
    if configFrame then configFrame:Hide() end
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function Config:Initialize()
    configFrame = CreateConfigFrame()
    blizzardPanel = CreateBlizzardPanel()
end
