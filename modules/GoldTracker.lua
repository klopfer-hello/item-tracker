--[[
    ItemTracker - GoldTracker Module
    Single Responsibility: Track the session value of looted items
    (vendor and auction house prices) and compute gold-per-hour rates.

    Subscribes to ITEM_VALUE (fires for every self-looted item,
    regardless of quality threshold).
    Reads raw gold from LootDetector:GetSessionGold().
    Vendor prices via GetItemInfo (return #11).
    AH prices via Auctionator API (optional, safe if not installed).

    Events fired:
        GOLD_RATES_UPDATED  (none)  — periodic rate recalculation
]]

local _, IT = ...
local GT = {}
IT.GoldTracker = GT

-- ============================================================================
-- Constants
-- ============================================================================

local UPDATE_INTERVAL = 10  -- seconds between GOLD_RATES_UPDATED fires
local MAX_RETRIES     = 10  -- per pending item

-- ============================================================================
-- State (session only, not persisted)
-- ============================================================================

local sessionStart  = 0
local vendorCopper  = 0
local ahCopper      = 0
local pendingItems  = {}  -- { { itemID, itemLink, count, retries } }

-- ============================================================================
-- Auctionator Integration (optional)
-- ============================================================================

local auctionatorChecked = false
local auctionatorAvailable = false

local function IsAuctionatorAvailable()
    if auctionatorChecked then return auctionatorAvailable end
    auctionatorChecked = true
    auctionatorAvailable = Auctionator
        and Auctionator.API
        and Auctionator.API.v1
        and Auctionator.API.v1.GetAuctionPriceByItemID
        and true or false
    return auctionatorAvailable
end

local function GetAHPrice(itemID)
    if not IsAuctionatorAvailable() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID,
                            "ItemTracker", itemID)
    if ok and price and price > 0 then return price end
    return nil
end

-- ============================================================================
-- Item Value Accumulation
-- ============================================================================

local function AddItemValue(itemID, itemLink, count)
    local _, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = GetItemInfo(itemLink)
    if not sellPrice then
        -- Item not cached; queue for retry
        table.insert(pendingItems, {
            itemID   = itemID,
            itemLink = itemLink,
            count    = count,
            retries  = 0,
        })
        return
    end

    -- Vendor value (always)
    vendorCopper = vendorCopper + (sellPrice * count)

    -- AH value (non-BoP items only; bindType 1 = Binds when Picked Up)
    if bindType ~= 1 then
        local ahPrice = GetAHPrice(itemID)
        if ahPrice then
            ahCopper = ahCopper + (ahPrice * count)
        else
            -- No AH data; use vendor price as fallback for AH column
            ahCopper = ahCopper + (sellPrice * count)
        end
    else
        -- BoP items: vendor value only (can't auction), mirror to AH for consistency
        ahCopper = ahCopper + (sellPrice * count)
    end
end

local function ProcessPendingItems()
    if #pendingItems == 0 then return end

    local still = {}
    for _, item in ipairs(pendingItems) do
        local _, _, _, _, _, _, _, _, _, _, sellPrice, _, _, bindType = GetItemInfo(item.itemLink)
        if sellPrice then
            vendorCopper = vendorCopper + (sellPrice * item.count)
            if bindType ~= 1 then
                local ahPrice = GetAHPrice(item.itemID)
                ahCopper = ahCopper + ((ahPrice or sellPrice) * item.count)
            else
                ahCopper = ahCopper + (sellPrice * item.count)
            end
        else
            item.retries = item.retries + 1
            if item.retries < MAX_RETRIES then
                table.insert(still, item)
            end
        end
    end
    pendingItems = still
end

-- ============================================================================
-- Event Handler
-- ============================================================================

local function OnItemValue(entry)
    if not entry.itemID or not entry.itemLink then return end
    AddItemValue(entry.itemID, entry.itemLink, entry.count or 1)
end

-- ============================================================================
-- Rate Calculation
-- ============================================================================

local function GetSessionHours()
    local elapsed = GetTime() - sessionStart
    return math.max(elapsed / 3600, 1 / 3600)  -- minimum ~1 second
end

function GT:GetRates()
    local rawCopper = IT.LootDetector and IT.LootDetector:GetSessionGold() or 0
    local hours = GetSessionHours()

    return {
        rawCopper      = rawCopper,
        vendorCopper   = vendorCopper,
        ahCopper       = ahCopper,
        hours          = hours,
        rawPerHour     = rawCopper / hours,
        vendorPerHour  = vendorCopper / hours,
        ahPerHour      = ahCopper / hours,
        hasAuctionator = IsAuctionatorAvailable(),
    }
end

function GT:GetSessionStart()
    return sessionStart
end

-- ============================================================================
-- Reset
-- ============================================================================

function GT:Reset()
    sessionStart = GetTime()
    vendorCopper = 0
    ahCopper     = 0
    wipe(pendingItems)
    -- Also reset raw gold in LootDetector
    if IT.LootDetector and IT.LootDetector.ResetSessionGold then
        IT.LootDetector:ResetSessionGold()
    end
    IT.Events:Fire("GOLD_RATES_UPDATED")
end

-- ============================================================================
-- Periodic Update Ticker
-- ============================================================================

local tickerFrame = CreateFrame("Frame")
local elapsed = 0

tickerFrame:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_INTERVAL then return end
    elapsed = 0

    ProcessPendingItems()
    IT.Events:Fire("GOLD_RATES_UPDATED")
end)

-- ============================================================================
-- Module Interface
-- ============================================================================

function GT:Initialize()
    sessionStart = GetTime()
    IT.Events:Subscribe("ITEM_VALUE", OnItemValue)
end
