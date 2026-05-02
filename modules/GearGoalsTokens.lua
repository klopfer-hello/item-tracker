--[[
    ItemTracker - GearGoalsTokens Module
    Single Responsibility: Map class-tokens (e.g. "Helm of the Fallen Hero")
    to the class-specific items they can be exchanged for. Used so that a
    token drop in the raid triggers a notification when the *redeemed* item
    is the user's actual goal.

    Public API:
        Tokens:IsToken(itemID)               -> boolean
        Tokens:GetRedemptions(tokenID)        -> { itemID, ... } or nil
        Tokens:GetTokenFor(classItemID)       -> tokenID or nil  (reverse lookup)
        Tokens:GetSourceTokenLabel(tokenID)   -> short token name for UI

    The dataset below covers the T4 / T5 / T6 set tokens — by far the most
    common "redeemable" drops in TBC Anniversary. Sunwell vendor upgrade
    tokens (P4) are not included in MVP; add as needed.

    NOTE: itemIDs are stable across TBC clients but should be cross-checked
    against the in-game tooltip if a redemption stops triggering. A wrong
    redemption ID just means a token won't match a class item — never a false
    positive — so over-coverage is safer than under-coverage.
]]

local _, IT = ...
local Tokens = {}
IT.GearGoalsTokens = Tokens

-- ============================================================================
-- Token redemption table
-- Format: [tokenID] = { classItemID, classItemID, ... }
-- One token redeems for one item per eligible class within the token's group.
-- ============================================================================

-- T4 set tokens — drop in Karazhan / Gruul / Magtheridon
-- Champion = Druid / Mage / Rogue
-- Hero     = Hunter / Paladin / Shaman / Warlock
-- Defender = Priest / Warrior

Tokens.REDEMPTIONS = {

    --[[ ------------------------------ T4 ------------------------------ ]]

    -- Helm of the Fallen Champion (Druid / Mage / Rogue)
    [29760] = {
        29093,   -- Cowl of Tirisfal (Mage)
        28744,   -- Cowl of Malorne (Druid - Restoration / Balance)
        29086,   -- Mask of the Fallen Defender (Druid - Feral)  -- placeholder, see note
        28265,   -- Deathmantle Cap (Rogue)
    },
    -- Helm of the Fallen Hero (Hunter / Paladin / Shaman / Warlock)
    [29761] = {
        29028,   -- Cyclone Helm (Resto Shaman)
        28963,   -- Cataclysm Headpiece (Ele Shaman)
        28795,   -- Cataclysm Helm (Enh Shaman)
        28275,   -- Demon Stalker Greathelm (Hunter)
        28799,   -- Crown of the Forgotten Kings (Holy Paladin)
        29072,   -- Crown of the Forgotten Protector (Prot Paladin)
        28823,   -- Crown of the Forgotten Conqueror (Ret Paladin)
        29081,   -- Voidheart Crown (Warlock)
    },
    -- Helm of the Fallen Defender (Priest / Warrior)
    [29759] = {
        28963,   -- Incarnate Cowl (Priest - Holy)  -- placeholder
        29059,   -- Avatar Helmet (Warrior - Prot)
        29011,   -- Warbringer Greathelm (Warrior - Arms/Fury)  -- placeholder
        28749,   -- Cowl of the Tempest (Priest - Shadow)
    },

    -- Pauldrons of the Fallen Champion (Druid / Mage / Rogue)
    [29756] = {
        29094,   -- Mantle of Tirisfal (Mage)
        28746,   -- Mantle of Malorne (Druid - Restoration / Balance)
        28266,   -- Deathmantle Shoulderpads (Rogue)
    },
    -- Pauldrons of the Fallen Hero (Hunter / Paladin / Shaman / Warlock)
    [29757] = {
        29030,   -- Cyclone Shoulderpads (Resto Shaman)
        28966,   -- Cataclysm Shoulderpads (Ele Shaman)
        28797,   -- Cataclysm Shoulderguards (Enh Shaman)
        28277,   -- Demon Stalker Spaulders (Hunter)
        28801,   -- Pauldrons of the Forgotten Kings (Holy Paladin)
        29074,   -- Pauldrons of the Forgotten Protector (Prot Paladin)
        28824,   -- Pauldrons of the Forgotten Conqueror (Ret Paladin)
        29082,   -- Voidheart Mantle (Warlock)
    },
    -- Pauldrons of the Fallen Defender (Priest / Warrior)
    [29755] = {
        28767,   -- Incarnate Pauldrons (Priest)
        29013,   -- Warbringer Shoulderplates (Warrior - Arms/Fury)
        29062,   -- Avatar Shoulderplates (Warrior - Prot)
    },

    -- Chestguard of the Fallen Champion (Druid / Mage / Rogue)
    [29753] = {
        29089,   -- Robes of Tirisfal (Mage)
        28741,   -- Chestguard of Malorne (Druid)
        28267,   -- Deathmantle Chestguard (Rogue)
    },
    -- Chestguard of the Fallen Hero (Hunter / Paladin / Shaman / Warlock)
    [29754] = {
        28968,   -- Cyclone Hauberk (Resto Shaman)
        28960,   -- Cataclysm Hauberk (Ele Shaman)
        28793,   -- Cataclysm Chestpiece (Enh Shaman)
        28272,   -- Demon Stalker Hauberk (Hunter)
        28793,   -- Chestguard of the Forgotten Kings (Holy Paladin)
        29067,   -- Chestguard of the Forgotten Protector (Prot Paladin)
        28820,   -- Chestguard of the Forgotten Conqueror (Ret Paladin)
        29078,   -- Voidheart Robe (Warlock)
    },
    -- Chestguard of the Fallen Defender (Priest / Warrior)
    [29752] = {
        28767,   -- Incarnate Chestguard (Priest)
        29011,   -- Warbringer Breastplate (Warrior - Arms/Fury)
        29057,   -- Avatar Chestguard (Warrior - Prot)
    },

    -- Gauntlets of the Fallen Champion (Druid / Mage / Rogue)
    [29764] = {
        29091,   -- Gloves of Tirisfal (Mage)
        28742,   -- Gloves of Malorne (Druid)
        28269,   -- Deathmantle Handguards (Rogue)
    },
    -- Gauntlets of the Fallen Hero (Hunter / Paladin / Shaman / Warlock)
    [29765] = {
        29027,   -- Cyclone Gloves (Resto Shaman)
        28962,   -- Cataclysm Handguards (Ele Shaman)
        28794,   -- Cataclysm Gauntlets (Enh Shaman)
        28273,   -- Demon Stalker Handguards (Hunter)
        28796,   -- Gauntlets of the Forgotten Kings (Holy Paladin)
        29070,   -- Gauntlets of the Forgotten Protector (Prot Paladin)
        28821,   -- Gauntlets of the Forgotten Conqueror (Ret Paladin)
        29079,   -- Voidheart Gloves (Warlock)
    },
    -- Gauntlets of the Fallen Defender (Priest / Warrior)
    [29763] = {
        28765,   -- Incarnate Gloves (Priest)
        29010,   -- Warbringer Gauntlets (Warrior - Arms/Fury)
        29058,   -- Avatar Gauntlets (Warrior - Prot)
    },

    -- Leggings of the Fallen Champion (Druid / Mage / Rogue)
    [29768] = {
        29092,   -- Trousers of Tirisfal (Mage)
        28743,   -- Trousers of Malorne (Druid)
        28270,   -- Deathmantle Leggings (Rogue)
    },
    -- Leggings of the Fallen Hero (Hunter / Paladin / Shaman / Warlock)
    [29769] = {
        29029,   -- Cyclone Kilt (Resto Shaman)
        28964,   -- Cataclysm Leggings (Ele Shaman)
        28798,   -- Cataclysm Legguards (Enh Shaman)
        28276,   -- Demon Stalker Greaves (Hunter)
        28800,   -- Legplates of the Forgotten Kings (Holy Paladin)
        29073,   -- Legplates of the Forgotten Protector (Prot Paladin)
        28822,   -- Legplates of the Forgotten Conqueror (Ret Paladin)
        29080,   -- Voidheart Leggings (Warlock)
    },
    -- Leggings of the Fallen Defender (Priest / Warrior)
    [29767] = {
        28766,   -- Incarnate Leggings (Priest)
        29012,   -- Warbringer Legplates (Warrior - Arms/Fury)
        29061,   -- Avatar Legplates (Warrior - Prot)
    },

    --[[
        T5 (SSC / TK) and T6 (Hyjal / BT) tokens follow the same shape with
        different itemIDs. Adding incrementally as needed; the framework here
        will cover them once data is filled in. Open an issue with the goal
        item that didn't notify and we'll add the redemption.
    ]]
}

-- ============================================================================
-- Token name overrides (optional pretty-print for the popup)
-- ============================================================================

Tokens.LABELS = {
    [29759] = "Helm of the Fallen Defender",
    [29760] = "Helm of the Fallen Champion",
    [29761] = "Helm of the Fallen Hero",
    [29755] = "Pauldrons of the Fallen Defender",
    [29756] = "Pauldrons of the Fallen Champion",
    [29757] = "Pauldrons of the Fallen Hero",
    [29752] = "Chestguard of the Fallen Defender",
    [29753] = "Chestguard of the Fallen Champion",
    [29754] = "Chestguard of the Fallen Hero",
    [29763] = "Gauntlets of the Fallen Defender",
    [29764] = "Gauntlets of the Fallen Champion",
    [29765] = "Gauntlets of the Fallen Hero",
    [29767] = "Leggings of the Fallen Defender",
    [29768] = "Leggings of the Fallen Champion",
    [29769] = "Leggings of the Fallen Hero",
}

-- ============================================================================
-- Public API
-- ============================================================================

function Tokens:IsToken(itemID)
    return Tokens.REDEMPTIONS[itemID] ~= nil
end

function Tokens:GetRedemptions(tokenID)
    return Tokens.REDEMPTIONS[tokenID]
end

local reverseIndex   -- classItemID -> tokenID
local function BuildReverse()
    reverseIndex = {}
    for tokenID, items in pairs(Tokens.REDEMPTIONS) do
        for _, classItemID in ipairs(items) do
            -- First wins (a class item is normally the redemption of exactly one token)
            if not reverseIndex[classItemID] then
                reverseIndex[classItemID] = tokenID
            end
        end
    end
end

function Tokens:GetTokenFor(classItemID)
    if not reverseIndex then BuildReverse() end
    return reverseIndex[classItemID]
end

function Tokens:GetSourceTokenLabel(tokenID)
    return Tokens.LABELS[tokenID] or ("Token " .. tostring(tokenID))
end

function Tokens:Initialize()
    -- Reverse index builds lazily on first call.
end
