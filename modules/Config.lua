--[[
    Klopfer's Item Tracker - Config Module
    Single Responsibility: Register the addon's settings with the modern
    Blizzard Settings panel using the auto-bound vertical layout API
    (Settings.RegisterAddOnSetting + Settings.CreateCheckbox/Slider/Dropdown),
    which gives us the same native look-and-feel as Molinari and Blizzard's
    own panels — no custom widgets, no custom palette.
]]

local _, IT = ...
local Config = {}
IT.Config = Config

-- ============================================================================
-- Quality dropdown values
-- ============================================================================

local QUALITY_OPTIONS = {
    { value = 0, label = "|cFF9D9D9DPoor|r" },
    { value = 1, label = "|cFFFFFFFFCommon|r" },
    { value = 2, label = "|cFF1EFF00Uncommon|r" },
    { value = 3, label = "|cFF0070DDRare|r" },
    { value = 4, label = "|cFFA335EEEpic|r" },
    { value = 5, label = "|cFFFF8000Legendary|r" },
}

local TOAST_DIRECTION_OPTIONS = {
    { value = true,  label = "Upward" },
    { value = false, label = "Downward" },
}

-- ============================================================================
-- Settings registration
-- ============================================================================

local function RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local category = Settings.RegisterVerticalLayoutCategory("Klopfer's Item Tracker")
    Settings.RegisterAddOnCategory(category)
    Config.category = category

    -- Helpers ---------------------------------------------------------------

    local function addCheckbox(key, default, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(
            category,
            "ItemTrackerDB_" .. key,
            key,
            IT.db.settings,
            "boolean",
            label,
            default)
        Settings.CreateCheckbox(category, setting, tooltip)
        if onChange then setting:SetValueChangedCallback(onChange) end
    end

    local function addSlider(key, default, label, tooltip, minVal, maxVal, step)
        local setting = Settings.RegisterAddOnSetting(
            category,
            "ItemTrackerDB_" .. key,
            key,
            IT.db.settings,
            "number",
            label,
            default)
        local options = Settings.CreateSliderOptions(minVal, maxVal, step)
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    local function addDropdown(key, default, label, tooltip, optsList)
        local setting = Settings.RegisterAddOnSetting(
            category,
            "ItemTrackerDB_" .. key,
            key,
            IT.db.settings,
            type(default),
            label,
            default)
        local function getOptions()
            local container = Settings.CreateControlTextContainer()
            for _, opt in ipairs(optsList) do
                container:Add(opt.value, opt.label)
            end
            return container:GetData()
        end
        Settings.CreateDropdown(category, setting, getOptions, tooltip)
    end

    -- General ---------------------------------------------------------------

    addCheckbox("enabled", true,
        "Enable Klopfer's Item Tracker",
        "Master switch for loot/roll tracking and toast notifications.")

    addCheckbox("locked", false,
        "Lock anchor bar position",
        "When locked, the anchor bar fades out and only reveals on mouseover.",
        function() if IT.UI and IT.UI.UpdateLockState then IT.UI:UpdateLockState() end end)

    addCheckbox("toastUpward", true,
        "Stack toasts upward",
        "Newest toast appears above the previous one. Uncheck to stack downward.",
        function() if IT.Toast and IT.Toast.RepositionAll then IT.Toast:RepositionAll() end end)

    addCheckbox("toastGold", false,
        "Show toasts for gold loot",
        "Display a toast notification when gold is looted.")

    addCheckbox("chatOutput", true,
        "Show chat messages",
        "Print loot and roll messages to the default chat frame.")

    addCheckbox("showMinimap", true,
        "Show minimap button",
        "Toggle the minimap button.",
        function() if IT.Minimap then IT.Minimap:UpdateVisibility() end end)

    -- Quality thresholds ----------------------------------------------------

    addDropdown("soloQualityThreshold", 2,
        "Solo loot — minimum quality",
        "Items below this quality won't trigger a toast when looted solo.",
        QUALITY_OPTIONS)

    addDropdown("groupQualityThreshold", 2,
        "Group / Raid loot — minimum quality",
        "Items below this quality won't trigger a toast when looted in a group.",
        QUALITY_OPTIONS)

    -- Toast / history sliders ----------------------------------------------

    addSlider("toastDuration", 8,
        "Toast duration (seconds)",
        "How long each toast notification stays on screen.",
        3, 30, 1)

    addSlider("toastMaxVisible", 5,
        "Maximum visible toasts",
        "Cap on how many toasts can be on screen at once.",
        1, 10, 1)

    addSlider("historySize", 100,
        "History size (max entries)",
        "How many loot history entries to keep before the oldest is dropped.",
        10, 500, 10)

    -- Scrolling loot text ---------------------------------------------------
    -- Independent of the history thresholds above: this shows EVERYTHING you
    -- loot as scrolling text and never writes to the loot-history table.

    addCheckbox("lootTextEnable", true,
        "Enable scrolling loot text",
        "Show items and money you loot as scrolling text on screen. Independent of the history quality thresholds above — position it with /kit loottext.")

    addCheckbox("lootTextShowItems", true,
        "Scrolling text — show items",
        "Scroll every item you loot (filtered only by the minimum quality below).")

    addCheckbox("lootTextShowMoney", true,
        "Scrolling text — show money",
        "Scroll each coin pickup as it happens.")

    addDropdown("lootTextQuality", 0,
        "Scrolling text — minimum quality",
        "Filters the scrolling display only (not the loot history). 'Poor' shows everything you loot.",
        QUALITY_OPTIONS)

    addDropdown("lootTextUp", true,
        "Scrolling text — direction",
        "Direction the text drifts as it fades.",
        TOAST_DIRECTION_OPTIONS)

    addSlider("lootTextScale", 1.0,
        "Scrolling text — scale",
        "Font size of the scrolling loot text.",
        0.5, 2.5, 0.05)

    addSlider("lootTextDuration", 3,
        "Scrolling text — duration (seconds)",
        "How long each scrolling line stays on screen.",
        1, 10, 1)
end

-- ============================================================================
-- Public API — open the Settings panel directly to our category.
-- ============================================================================

local function OpenToPanel()
    if not (Settings and Settings.OpenToCategory) then return end
    if not Config.category then return end
    Settings.OpenToCategory(Config.category:GetID())
end

function Config:Toggle()
    if SettingsPanel and SettingsPanel:IsShown() then
        SettingsPanel:Hide()
    else
        OpenToPanel()
    end
end

function Config:Show() OpenToPanel() end

function Config:Hide()
    if SettingsPanel and SettingsPanel:IsShown() then
        SettingsPanel:Hide()
    end
end

-- ============================================================================
-- Module Interface
-- ============================================================================

function Config:Initialize()
    RegisterSettings()
end
