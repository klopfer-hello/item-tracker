--[[
    ItemTracker - GearGoalsTooltip Module
    Single Responsibility: Add a "On your <spec> list (Pn, rank N)" line to
    GameTooltip whenever the hovered item matches an entry on this character's
    goal list (any spec, any phase).

    Active spec: full-color line (gold rank label).
    Other spec: dimmed line ("On <spec> list").
    Obtained:    strike-through-style "(have)" suffix.
]]

local _, IT = ...
local TT = {}
IT.GearGoalsTooltip = TT

-- ============================================================================
-- Helpers
-- ============================================================================

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function PrettyLoadout(loadoutID)
    local GG = IT.GearGoals
    return (GG and GG.GetLoadoutName) and GG:GetLoadoutName(loadoutID) or loadoutID
end

local GOLD = "|cFFFFCC33"
local DIM  = "|cFF6E6E78"
local PINK = "|cFFEE6680"
local GREEN = "|cFF55CC66"

--- Convert a loadout's `#RRGGBB` colour into a WoW colour escape, falling
--- back to GOLD for the main loadout / DIM for an alt without a colour.
local function loadoutColorEscape(loadoutID, isMain)
    local GG = IT.GearGoals
    local loadout = GG and GG.GetLoadoutByID and GG:GetLoadoutByID(loadoutID)
    local hex = loadout and loadout.color
    if hex and type(hex) == "string" then
        local clean = (hex:sub(1, 1) == "#") and hex:sub(2) or hex
        if clean:match("^%x%x%x%x%x%x$") then
            return "|cFF" .. clean:upper()
        end
    end
    return isMain and GOLD or DIM
end

-- ============================================================================
-- Tooltip line builder
-- ============================================================================

local function AppendGoalLines(tooltip, itemID)
    local GG = IT.GearGoals
    if not GG or not GG.FindAllMatches then return end

    local matches = GG:FindAllMatches(itemID)

    -- Token expansion: hovering a token like "Helm of the Fallen Hero" should
    -- surface the user's class-specific goal that the token redeems for.
    local Tokens     = IT.GearGoalsTokens
    local tokenMatches = {}
    if Tokens and Tokens:IsToken(itemID) then
        -- Hovering a token: surface every goal on this character whose
        -- item auto-derives back to that token. Same logic the detector uses.
        for _, m in ipairs(GG:FindAllMatchesForToken(itemID)) do
            m._redeemFrom = itemID
            m._goalItemID = m.goal.itemID
            table.insert(tokenMatches, m)
        end
    end

    if #matches == 0 and #tokenMatches == 0 then return end

    -- Stitch token matches in alongside direct matches
    for _, m in ipairs(tokenMatches) do table.insert(matches, m) end

    local mainLoadout = GG:GetMainLoadoutID()
    local current     = GG:GetCurrentPhase()

    -- Group matches by loadoutID (specKey field on the match is the loadout)
    local byLoadout = {}
    for _, m in ipairs(matches) do
        byLoadout[m.specKey] = byLoadout[m.specKey] or {}
        table.insert(byLoadout[m.specKey], m)
    end

    -- Main loadout first, then others
    local order = {}
    if byLoadout[mainLoadout] then table.insert(order, mainLoadout) end
    for k in pairs(byLoadout) do
        if k ~= mainLoadout then table.insert(order, k) end
    end

    tooltip:AddLine(" ")
    for _, loadoutID in ipairs(order) do
        local entries = byLoadout[loadoutID]
        local isMain  = (loadoutID == mainLoadout)
        -- Use the loadout's colour swatch (when set) so the tooltip lines
        -- match the sidebar swatch the user picked. Falls back to GOLD/DIM.
        local color   = loadoutColorEscape(loadoutID, isMain)
        local prefix  = isMain
            and (color .. "On your " .. PrettyLoadout(loadoutID) .. " list:|r")
            or  (color .. "Also on " .. PrettyLoadout(loadoutID) .. ":|r")
        tooltip:AddLine(prefix)
        for _, m in ipairs(entries) do
            local phaseLabel = GG.PHASE_LABEL[m.phase] or m.phase
            local rankColor  = color
            local statusSuffix = ""
            if m.goal and m.goal.obtained then
                statusSuffix = "  " .. GREEN .. "(have)|r"
            else
                local status = GG:StatusFor(loadoutID, m.phase, m.slotID, m.goal)
                if status == GG.STATUS.EQUIPPED then
                    statusSuffix = "  " .. GOLD .. "(equipped)|r"
                elseif status == GG.STATUS.OWNED then
                    statusSuffix = "  " .. GREEN .. "(owned)|r"
                elseif status == GG.STATUS.LOCKED then
                    statusSuffix = "  " .. DIM .. "(future phase)|r"
                end
            end
            -- Token entry: prefix with the redemption arrow so the user sees
            -- which class item this token unlocks for them.
            local prefix = ""
            if m._goalItemID then
                local goalName = GetItemInfo(m._goalItemID) or ("Item " .. m._goalItemID)
                prefix = DIM .. "redeems for " .. goalName .. "|r — "
            end
            tooltip:AddLine(string.format("  %s%s%s · rank #%d|r%s",
                prefix, rankColor, phaseLabel, m.rank, statusSuffix))
        end
    end
    tooltip:Show()
end

-- ============================================================================
-- Hooks
-- ============================================================================

local function OnTooltipSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if not link then return end
    local itemID = ItemIDFromLink(link)
    if not itemID then return end
    -- Populate the autocomplete cache opportunistically — every item the
    -- player hovers becomes searchable in the add dialog.
    if IT.GearGoals and IT.GearGoals.RememberItem then
        IT.GearGoals:RememberItem(itemID)
    end
    AppendGoalLines(tooltip, itemID)
end

function TT:Initialize()
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    IT:Debug("GearGoalsTooltip initialized")
end
