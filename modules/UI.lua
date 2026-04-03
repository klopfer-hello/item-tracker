--[[
    ItemTracker - UI Module
    Single Responsibility: Manage the movable anchor bar (invisible
    when locked) and a standalone loot history pop-out window with
    name / quality / location filters.

    The anchor bar is always present as a positioning frame for toasts.
    When unlocked it renders as a thin glassy strip for dragging.
    When locked it becomes fully transparent (zero visual footprint).

    Listens to:
        HISTORY_UPDATED — refresh the history scroll content
        PLAYER_READY    — restore saved position
]]

local _, IT = ...
local UI = {}
IT.UI = UI

-- ============================================================================
-- Design Constants
-- ============================================================================

local BAR_WIDTH         = 280
local BAR_HEIGHT        = 22
local HISTORY_WIDTH     = 340
local HISTORY_HEIGHT    = 360
local HEADER_HEIGHT     = 60       -- title + filter row
local ROW_HEIGHT        = 36
local ROW_ICON_SIZE     = 28
local ROW_PADDING       = 6
local SCROLL_STEP       = ROW_HEIGHT * 3

-- Glassy palette
local CD = {
    bg      = { 0.04, 0.04, 0.06 },  bgA  = 0.93,
    border  = { 0.18, 0.18, 0.23 },  borA = 0.80,
    accent  = { 0.28, 0.74, 0.97 },
    label   = { 0.40, 0.40, 0.45 },
    value   = { 0.82, 0.84, 0.88 },
    barBg   = { 0.07, 0.07, 0.09 },
}

-- ============================================================================
-- Frames
-- ============================================================================

local barFrame              -- anchor (always exists, invisible when locked)
local historyFrame          -- standalone pop-out window
local scrollFrame, scrollChild, scrollBar
local filterNameBox         -- EditBox for name search
local filterQualityBtn      -- quality filter button
local filterQuality = nil   -- nil = all, or 0-5

-- ============================================================================
-- Thin Border Helper
-- ============================================================================

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
-- Anchor Bar
-- ============================================================================

local function ShowBar()
    if not barFrame then return end
    barFrame:EnableMouse(true)
    barFrame:SetBackdropColor(CD.bg[1], CD.bg[2], CD.bg[3], 0.82)
    barFrame:SetBackdropBorderColor(CD.accent[1], CD.accent[2], CD.accent[3], 0.40)
    barFrame.title:SetText("|cFF00D1FFItemTracker|r")
    barFrame.grip:SetText("|cFF666666::::|r")
end

local function HideBar()
    if not barFrame then return end
    barFrame:SetBackdropColor(0, 0, 0, 0)
    barFrame:SetBackdropBorderColor(0, 0, 0, 0)
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

local function CreateAnchorBar()
    local f = CreateFrame("Frame", "ItemTrackerBar", UIParent, "BackdropTemplate")
    f:SetSize(BAR_WIDTH, BAR_HEIGHT)
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

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

    -- Click to toggle history
    f:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            UI:ToggleHistory()
        elseif button == "RightButton" then
            if IT.Config and IT.Config.Toggle then
                IT.Config:Toggle()
            end
        end
    end)

    -- Tooltip + hover reveal when locked
    f:SetScript("OnEnter", function(self)
        if IT.db.settings.locked then
            ShowBar()
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("ItemTracker", CD.accent[1], CD.accent[2], CD.accent[3])
        GameTooltip:AddLine("Left-click: Toggle history", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Settings", 0.7, 0.7, 0.7)
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
-- History Filters
-- ============================================================================

local QUALITY_FILTER_OPTIONS = {
    { value = nil, label = "All" },
    { value = 2,   label = "|cFF1EFF00Uncommon+|r" },
    { value = 3,   label = "|cFF0070DDRare+|r" },
    { value = 4,   label = "|cFFA335EEEpic+|r" },
    { value = 5,   label = "|cFFFF8000Legendary|r" },
}

local function GetFilteredEntries()
    local all = IT.LootHistory and IT.LootHistory:GetAll() or {}
    local nameFilter = filterNameBox and filterNameBox:GetText():trim():lower() or ""

    local result = {}
    for _, entry in ipairs(all) do
        -- Quality filter
        if filterQuality and (entry.quality or 0) < filterQuality then
            -- skip
        -- Name filter (matches item name or player name)
        elseif nameFilter ~= "" then
            local itemName = entry.itemLink and entry.itemLink:match("%[(.-)%]") or ""
            local player = entry.player or ""
            if itemName:lower():find(nameFilter, 1, true)
            or player:lower():find(nameFilter, 1, true) then
                table.insert(result, entry)
            end
        else
            table.insert(result, entry)
        end
    end
    return result
end

-- ============================================================================
-- History Row
-- ============================================================================

local historyRows = {}

local function CreateHistoryRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(HISTORY_WIDTH - 20, ROW_HEIGHT)

    -- Alternating stripe
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.02)
    end

    -- Icon
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", ROW_PADDING, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Icon quality border
    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetSize(ROW_ICON_SIZE + 2, ROW_ICON_SIZE + 2)
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")

    -- Item name
    row.itemName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.itemName:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.itemName:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.itemName:SetJustifyH("LEFT")
    row.itemName:SetWordWrap(false)

    -- Player name
    row.playerName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.playerName:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.playerName:SetJustifyH("LEFT")
    row.playerName:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    -- Time ago
    row.timeAgo = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.timeAgo:SetPoint("RIGHT", row, "RIGHT", -ROW_PADDING, 0)
    row.timeAgo:SetJustifyH("RIGHT")
    row.timeAgo:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    -- Roll indicator
    row.rollIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.rollIcon:SetPoint("RIGHT", row.timeAgo, "LEFT", -4, 0)
    row.rollIcon:SetTextColor(0.9, 0.75, 0.2)

    -- Tooltip on hover
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.data and self.data.itemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.data.itemLink)
            if self.data.wasRolled and self.data.rolls then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Roll Results:", 1, 0.82, 0)
                for _, roll in ipairs(self.data.rolls) do
                    local numStr = (roll.number and roll.number > 0) and (" - " .. roll.number) or ""
                    GameTooltip:AddLine("  " .. roll.player .. ": " .. roll.rollType .. numStr,
                                        0.8, 0.8, 0.8)
                end
                if self.data.winner then
                    GameTooltip:AddLine("Winner: " .. self.data.winner, 0, 1, 0)
                end
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:Hide()
    return row
end

-- ============================================================================
-- History Pop-Out Window
-- ============================================================================

local function CreateHistoryPanel()
    local f = CreateFrame("Frame", "ItemTrackerHistory", UIParent, "BackdropTemplate")
    f:SetSize(HISTORY_WIDTH, HISTORY_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)

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

    -- ESC to close
    table.insert(UISpecialFrames, "ItemTrackerHistory")

    -- ── Title bar ──
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("|cFF00D1FFLoot History|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("|cFFAAAAAA\195\151|r")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function(self) self.text:SetText("|cFFFFFFFF\195\151|r") end)
    closeBtn:SetScript("OnLeave", function(self) self.text:SetText("|cFFAAAAAA\195\151|r") end)

    -- Item count + session gold (right of title)
    f.countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.countLabel:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -8, -3)
    f.countLabel:SetJustifyH("RIGHT")
    f.countLabel:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    f.goldLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.goldLabel:SetPoint("LEFT", title, "RIGHT", 10, 0)
    f.goldLabel:SetJustifyH("LEFT")
    f.goldLabel:SetTextColor(0.95, 0.85, 0.3)

    -- ── Filter row ──
    -- Name search box
    local searchBox = CreateFrame("EditBox", "ItemTrackerSearchBox", f, "BackdropTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontNormalSmall)
    searchBox:SetTextColor(CD.value[1], CD.value[2], CD.value[3])
    searchBox:SetMaxLetters(40)

    local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints()
    searchBg:SetColorTexture(CD.barBg[1], CD.barBg[2], CD.barBg[3], 1)
    AddThinBorder(searchBox, CD.border[1], CD.border[2], CD.border[3], 0.6)

    -- Placeholder text
    searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchBox.placeholder:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
    searchBox.placeholder:SetText("Search name or player...")
    searchBox.placeholder:SetTextColor(CD.label[1], CD.label[2], CD.label[3])

    searchBox:SetTextInsets(6, 6, 0, 0)

    searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text and text ~= "" then
            self.placeholder:Hide()
        else
            self.placeholder:Show()
        end
        UI:RefreshHistory()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() ~= "" then self.placeholder:Hide() end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end)
    filterNameBox = searchBox

    -- Quality filter button
    local qBtn = CreateFrame("Button", nil, f)
    qBtn:SetSize(110, 20)
    qBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)

    local qBg = qBtn:CreateTexture(nil, "BACKGROUND")
    qBg:SetAllPoints()
    qBg:SetColorTexture(CD.barBg[1], CD.barBg[2], CD.barBg[3], 1)
    AddThinBorder(qBtn, CD.border[1], CD.border[2], CD.border[3], 0.6)

    qBtn.label = qBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qBtn.label:SetPoint("CENTER")
    qBtn.label:SetText("All")
    filterQualityBtn = qBtn

    -- Quality dropdown menu
    local qMenu = CreateFrame("Frame", nil, qBtn, "BackdropTemplate")
    qMenu:SetSize(110, #QUALITY_FILTER_OPTIONS * 20 + 4)
    qMenu:SetPoint("TOP", qBtn, "BOTTOM", 0, 1)
    qMenu:SetFrameStrata("TOOLTIP")
    qMenu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    qMenu:SetBackdropColor(CD.bg[1], CD.bg[2], CD.bg[3], 0.96)
    qMenu:SetBackdropBorderColor(CD.border[1], CD.border[2], CD.border[3], CD.borA)
    qMenu:Hide()

    for i, opt in ipairs(QUALITY_FILTER_OPTIONS) do
        local item = CreateFrame("Button", nil, qMenu)
        item:SetSize(106, 20)
        item:SetPoint("TOPLEFT", qMenu, "TOPLEFT", 2, -(i - 1) * 20 - 2)

        item.text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        item.text:SetPoint("LEFT", item, "LEFT", 6, 0)
        item.text:SetText(opt.label)

        local hl = item:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(CD.accent[1], CD.accent[2], CD.accent[3], 0.15)

        item:SetScript("OnClick", function()
            filterQuality = opt.value
            qBtn.label:SetText(opt.label)
            qMenu:Hide()
            UI:RefreshHistory()
        end)
    end

    qBtn:SetScript("OnClick", function()
        if qMenu:IsShown() then qMenu:Hide() else qMenu:Show() end
    end)

    qMenu:SetScript("OnShow", function(self)
        local grace = 0.3
        self:SetScript("OnUpdate", function(_, dt)
            if grace > 0 then grace = grace - dt; return end
            if not qBtn:IsMouseOver() and not self:IsMouseOver() then
                self:Hide()
            end
        end)
    end)
    qMenu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

    -- ── Divider below filters ──
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  f, "TOPLEFT",  8, -HEADER_HEIGHT)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -HEADER_HEIGHT)
    divider:SetColorTexture(CD.border[1], CD.border[2], CD.border[3], 0.5)

    -- ── Scroll area ──
    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     6, -(HEADER_HEIGHT + 4))
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 6)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(HISTORY_WIDTH - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Scroll bar thumb
    scrollBar = CreateFrame("Frame", nil, f)
    scrollBar:SetSize(4, 1)
    scrollBar:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -4, -(HEADER_HEIGHT + 4))
    scrollBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 6)

    scrollBar.thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    scrollBar.thumb:SetColorTexture(CD.accent[1], CD.accent[2], CD.accent[3], 0.4)
    scrollBar.thumb:SetSize(4, 30)
    scrollBar.thumb:SetPoint("TOP", scrollBar, "TOP")

    -- Mouse wheel
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local newScroll = math.max(0, math.min(maxScroll, current - delta * SCROLL_STEP))
        self:SetVerticalScroll(newScroll)
        UI:UpdateScrollThumb()
    end)

    f:Hide()
    return f
end

-- ============================================================================
-- Scroll Thumb
-- ============================================================================

function UI:UpdateScrollThumb()
    if not scrollBar or not scrollFrame then return end
    local maxScroll = math.max(1, scrollChild:GetHeight() - scrollFrame:GetHeight())
    local scrollRatio = scrollFrame:GetVerticalScroll() / maxScroll
    local trackHeight = scrollBar:GetHeight()
    local thumbHeight = math.max(20, trackHeight * (scrollFrame:GetHeight() / math.max(1, scrollChild:GetHeight())))

    scrollBar.thumb:SetHeight(thumbHeight)
    scrollBar.thumb:ClearAllPoints()
    local offset = scrollRatio * (trackHeight - thumbHeight)
    scrollBar.thumb:SetPoint("TOP", scrollBar, "TOP", 0, -offset)

    scrollBar.thumb:SetShown(scrollChild:GetHeight() > scrollFrame:GetHeight())
end

-- ============================================================================
-- History Rendering
-- ============================================================================

function UI:RefreshHistory()
    if not historyFrame or not historyFrame:IsShown() then return end

    local entries = GetFilteredEntries()
    local total = IT.LootHistory and IT.LootHistory:GetCount() or 0
    local count = #entries

    -- Update count label
    if count == total then
        historyFrame.countLabel:SetText(count .. " items")
    else
        historyFrame.countLabel:SetText(count .. "/" .. total)
    end

    -- Update session gold
    local copper = IT.LootDetector and IT.LootDetector:GetSessionGold() or 0
    if copper > 0 then
        local gold   = math.floor(copper / 10000)
        local silver = math.floor((copper % 10000) / 100)
        local cop    = copper % 100
        local parts = {}
        if gold > 0 then table.insert(parts, gold .. "g") end
        if silver > 0 then table.insert(parts, silver .. "s") end
        if cop > 0 then table.insert(parts, cop .. "c") end
        historyFrame.goldLabel:SetText("Gold this session: " .. table.concat(parts, " "))
    else
        historyFrame.goldLabel:SetText("")
    end

    -- Create/reuse rows
    for i, entry in ipairs(entries) do
        local row = historyRows[i]
        if not row then
            row = CreateHistoryRow(scrollChild, i)
            historyRows[i] = row
        end

        row.data = entry

        -- Icon
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Quality border
        local r, g, b = IT:GetQualityColor(entry.quality or 0)
        row.iconBorder:SetColorTexture(r, g, b, 0.4)

        -- Item name
        local hex = IT:GetQualityHex(entry.quality or 0)
        local name = entry.itemLink and entry.itemLink:match("%[(.-)%]") or "Unknown"
        row.itemName:SetText(hex .. name .. "|r")

        -- Player
        if entry.isSelf then
            row.playerName:SetText("|cFFAAFFAAYou|r")
        else
            row.playerName:SetText(entry.player or "")
        end

        -- Time ago
        row.timeAgo:SetText(IT:FormatTimeAgo(entry.timestamp))

        -- Roll indicator
        if entry.wasRolled then
            row.rollIcon:SetText("R")
            row.rollIcon:Show()
        else
            row.rollIcon:SetText("")
            row.rollIcon:Hide()
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:Show()
    end

    -- Hide excess rows
    for i = count + 1, #historyRows do
        historyRows[i]:Hide()
    end

    -- Scroll child height
    scrollChild:SetHeight(math.max(1, count * ROW_HEIGHT))
    UI:UpdateScrollThumb()
end

-- ============================================================================
-- Periodic time-ago refresh
-- ============================================================================

local timerFrame = CreateFrame("Frame")
local refreshElapsed = 0

timerFrame:SetScript("OnUpdate", function(self, dt)
    refreshElapsed = refreshElapsed + dt
    if refreshElapsed < 10 then return end
    refreshElapsed = 0
    if historyFrame and historyFrame:IsShown() then
        UI:RefreshHistory()
    end
end)

-- ============================================================================
-- Toggle
-- ============================================================================

function UI:ToggleHistory()
    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        UI:RefreshHistory()
        historyFrame:Show()
    end
end

function UI:Toggle()
    UI:ToggleHistory()
end

function UI:Show()
    barFrame:Show()
end

function UI:Hide()
    barFrame:Hide()
    if historyFrame then historyFrame:Hide() end
end

function UI:IsShown()
    return barFrame and barFrame:IsShown()
end

function UI:GetAnchorFrame()
    return barFrame
end

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

-- Called by Config when lock setting changes
function UI:UpdateLockState()
    UpdateBarVisibility()
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function UI:Initialize()
    barFrame = CreateAnchorBar()
    historyFrame = CreateHistoryPanel()

    -- Give Toast module the anchor reference
    if IT.Toast then
        IT.Toast:SetAnchor(barFrame)
    end

    -- Event subscriptions
    IT.Events:Subscribe("HISTORY_UPDATED", function() UI:RefreshHistory() end)
    IT.Events:Subscribe("GOLD_LOOTED", function() UI:RefreshHistory() end)
    IT.Events:Subscribe("PLAYER_READY", RestorePosition)
end
