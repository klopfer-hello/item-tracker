--[[
    ItemTracker - GearGoalsTokens Module
    Single Responsibility: Map a tier-set class item to the class-token that
    redeems for it (and back), so a token drop in the raid triggers a
    notification on every wishlist item it can be exchanged into.

    Auto-derivation, no per-item hardcoding:

      GetItemInfo(itemID) returns
          equipLoc (9th)  -> piece slot (Helm / Pauldrons / Chestguard / ...)
          setID    (16th) -> static AtlasLoot tier-set ID

      setID -> { tier, class }    (table below, lifted from
                                   AtlasLootClassic_DungeonsAndRaids/data-tbc.lua)
      class -> token group        (Champion/Hero/Defender for T4-T5,
                                   Conqueror/Protector/Vanquisher for T6)
      (tier, group, slot) -> token itemID  (table below; from grepping the
                                            same data file for token names)

    Public API:
        Tokens:IsToken(itemID)        -> boolean
        Tokens:GetTokenFor(itemID)    -> tokenID | nil
        Tokens:GetSourceTokenLabel(t) -> short label string
]]

local _, IT = ...
local Tokens = {}
IT.GearGoalsTokens = Tokens

-- ============================================================================
-- Token IDs by (tier, group, slot)
-- Source: AtlasLootClassic_DungeonsAndRaids/data-tbc.lua (boss tables).
-- T4 / T5 use Champion / Hero / Defender; T6 uses Conqueror / Protector /
-- Vanquisher (and adds Sunwell vendor pieces for Bracers / Belt / Boots).
-- ============================================================================

local TOKEN_BY_TIER_GROUP_SLOT = {
    T4 = {
        Champion = { Helm = 29760, Pauldrons = 29763, Chestguard = 29754, Gloves = 29757, Leggings = 29766 },
        Hero     = { Helm = 29759, Pauldrons = 29762, Chestguard = 29755, Gloves = 29756, Leggings = 29765 },
        Defender = { Helm = 29761, Pauldrons = 29764, Chestguard = 29753, Gloves = 29758, Leggings = 29767 },
    },
    T5 = {
        Champion = { Helm = 30242, Pauldrons = 30248, Chestguard = 30236, Gloves = 30239, Leggings = 30245 },
        Hero     = { Helm = 30244, Pauldrons = 30250, Chestguard = 30238, Gloves = 30241, Leggings = 30247 },
        Defender = { Helm = 30243, Pauldrons = 30249, Chestguard = 30237, Gloves = 30240, Leggings = 30246 },
    },
    T6 = {
        Conqueror  = { Helm = 31097, Pauldrons = 31101, Chestguard = 31089, Gloves = 31092, Leggings = 31098,
                       Bracers = 34848, Belt = 34853, Boots = 34856 },
        Protector  = { Helm = 31095, Pauldrons = 31103, Chestguard = 31091, Gloves = 31094, Leggings = 31100,
                       Bracers = 34851, Belt = 34854, Boots = 34857 },
        Vanquisher = { Helm = 31096, Pauldrons = 31102, Chestguard = 31090, Gloves = 31093, Leggings = 31099,
                       Bracers = 34852, Belt = 34855, Boots = 34858 },
    },
}

-- Pretty labels for the popup / tooltip lines.
Tokens.LABELS = {
    -- T4
    [29760] = "Helm of the Fallen Champion",
    [29761] = "Helm of the Fallen Defender",
    [29759] = "Helm of the Fallen Hero",
    [29763] = "Pauldrons of the Fallen Champion",
    [29764] = "Pauldrons of the Fallen Defender",
    [29762] = "Pauldrons of the Fallen Hero",
    [29754] = "Chestguard of the Fallen Champion",
    [29753] = "Chestguard of the Fallen Defender",
    [29755] = "Chestguard of the Fallen Hero",
    [29757] = "Gloves of the Fallen Champion",
    [29758] = "Gloves of the Fallen Defender",
    [29756] = "Gloves of the Fallen Hero",
    [29766] = "Leggings of the Fallen Champion",
    [29767] = "Leggings of the Fallen Defender",
    [29765] = "Leggings of the Fallen Hero",
    -- T5
    [30242] = "Helm of the Vanquished Champion",
    [30243] = "Helm of the Vanquished Defender",
    [30244] = "Helm of the Vanquished Hero",
    [30248] = "Pauldrons of the Vanquished Champion",
    [30249] = "Pauldrons of the Vanquished Defender",
    [30250] = "Pauldrons of the Vanquished Hero",
    [30236] = "Chestguard of the Vanquished Champion",
    [30237] = "Chestguard of the Vanquished Defender",
    [30238] = "Chestguard of the Vanquished Hero",
    [30239] = "Gloves of the Vanquished Champion",
    [30240] = "Gloves of the Vanquished Defender",
    [30241] = "Gloves of the Vanquished Hero",
    [30245] = "Leggings of the Vanquished Champion",
    [30246] = "Leggings of the Vanquished Defender",
    [30247] = "Leggings of the Vanquished Hero",
    -- T6
    [31097] = "Helm of the Forgotten Conqueror",
    [31095] = "Helm of the Forgotten Protector",
    [31096] = "Helm of the Forgotten Vanquisher",
    [31101] = "Pauldrons of the Forgotten Conqueror",
    [31103] = "Pauldrons of the Forgotten Protector",
    [31102] = "Pauldrons of the Forgotten Vanquisher",
    [31089] = "Chestguard of the Forgotten Conqueror",
    [31091] = "Chestguard of the Forgotten Protector",
    [31090] = "Chestguard of the Forgotten Vanquisher",
    [31092] = "Gloves of the Forgotten Conqueror",
    [31094] = "Gloves of the Forgotten Protector",
    [31093] = "Gloves of the Forgotten Vanquisher",
    [31098] = "Leggings of the Forgotten Conqueror",
    [31100] = "Leggings of the Forgotten Protector",
    [31099] = "Leggings of the Forgotten Vanquisher",
    [34848] = "Bracers of the Forgotten Conqueror",
    [34851] = "Bracers of the Forgotten Protector",
    [34852] = "Bracers of the Forgotten Vanquisher",
    [34853] = "Belt of the Forgotten Conqueror",
    [34854] = "Belt of the Forgotten Protector",
    [34855] = "Belt of the Forgotten Vanquisher",
    [34856] = "Boots of the Forgotten Conqueror",
    [34857] = "Boots of the Forgotten Protector",
    [34858] = "Boots of the Forgotten Vanquisher",
}

-- ============================================================================
-- Set ID -> { tier, class }
-- AtlasLoot's T4_SET / T5_SET / T6_SET tables list every class+spec set ID
-- with a class comment; this map is a transcription of those.
-- ============================================================================

local SET_TO_TIER_CLASS = {
    -- T4
    [645] = { tier = "T4", class = "WARLOCK" },
    [663] = { tier = "T4", class = "PRIEST"  },
    [664] = { tier = "T4", class = "PRIEST"  },
    [621] = { tier = "T4", class = "ROGUE"   },
    [651] = { tier = "T4", class = "HUNTER"  },
    [654] = { tier = "T4", class = "WARRIOR" },
    [655] = { tier = "T4", class = "WARRIOR" },
    [648] = { tier = "T4", class = "MAGE"    },
    [638] = { tier = "T4", class = "DRUID"   },
    [639] = { tier = "T4", class = "DRUID"   },
    [640] = { tier = "T4", class = "DRUID"   },
    [631] = { tier = "T4", class = "SHAMAN"  },
    [632] = { tier = "T4", class = "SHAMAN"  },
    [633] = { tier = "T4", class = "SHAMAN"  },
    [624] = { tier = "T4", class = "PALADIN" },
    [625] = { tier = "T4", class = "PALADIN" },
    [626] = { tier = "T4", class = "PALADIN" },
    -- T5
    [646] = { tier = "T5", class = "WARLOCK" },
    [665] = { tier = "T5", class = "PRIEST"  },
    [666] = { tier = "T5", class = "PRIEST"  },
    [622] = { tier = "T5", class = "ROGUE"   },
    [652] = { tier = "T5", class = "HUNTER"  },
    [656] = { tier = "T5", class = "WARRIOR" },
    [657] = { tier = "T5", class = "WARRIOR" },
    [649] = { tier = "T5", class = "MAGE"    },
    [642] = { tier = "T5", class = "DRUID"   },
    [643] = { tier = "T5", class = "DRUID"   },
    [641] = { tier = "T5", class = "DRUID"   },
    [634] = { tier = "T5", class = "SHAMAN"  },
    [635] = { tier = "T5", class = "SHAMAN"  },
    [636] = { tier = "T5", class = "SHAMAN"  },
    [627] = { tier = "T5", class = "PALADIN" },
    [628] = { tier = "T5", class = "PALADIN" },
    [629] = { tier = "T5", class = "PALADIN" },
    -- T6
    [670] = { tier = "T6", class = "WARLOCK" },
    [675] = { tier = "T6", class = "PRIEST"  },
    [674] = { tier = "T6", class = "PRIEST"  },
    [668] = { tier = "T6", class = "ROGUE"   },
    [669] = { tier = "T6", class = "HUNTER"  },
    [673] = { tier = "T6", class = "WARRIOR" },
    [672] = { tier = "T6", class = "WARRIOR" },
    [671] = { tier = "T6", class = "MAGE"    },
    [678] = { tier = "T6", class = "DRUID"   },
    [677] = { tier = "T6", class = "DRUID"   },
    [676] = { tier = "T6", class = "DRUID"   },
    [683] = { tier = "T6", class = "SHAMAN"  },
    [684] = { tier = "T6", class = "SHAMAN"  },
    [682] = { tier = "T6", class = "SHAMAN"  },
    [681] = { tier = "T6", class = "PALADIN" },
    [679] = { tier = "T6", class = "PALADIN" },
    [680] = { tier = "T6", class = "PALADIN" },
}

-- Class -> token group per tier. Verified against the in-game tooltip
-- "Classes:" line on the actual tokens; T4/T5 have 3 classes per group:
--   Champion = Druid, Rogue, Shaman
--   Hero     = Hunter, Mage, Warlock
--   Defender = Paladin, Priest, Warrior
-- (The earlier table had Shaman/Paladin in Hero and Mage in Champion,
-- which mis-routed Shaman T4 pieces — Cyclone — to Hero tokens.)
local GROUP_T4_T5 = {
    DRUID = "Champion", ROGUE = "Champion", SHAMAN = "Champion",
    HUNTER = "Hero",    MAGE  = "Hero",     WARLOCK = "Hero",
    PALADIN = "Defender", PRIEST = "Defender", WARRIOR = "Defender",
}

local GROUP_T6 = {
    PALADIN = "Conqueror", PRIEST = "Conqueror", WARLOCK = "Conqueror",
    HUNTER = "Protector", SHAMAN = "Protector", WARRIOR = "Protector",
    DRUID = "Vanquisher", MAGE = "Vanquisher", ROGUE = "Vanquisher",
}

-- equipLoc -> piece-slot key
local SLOT_KEY = {
    INVTYPE_HEAD     = "Helm",
    INVTYPE_SHOULDER = "Pauldrons",
    INVTYPE_CHEST    = "Chestguard",
    INVTYPE_ROBE     = "Chestguard",
    INVTYPE_HAND     = "Gloves",
    INVTYPE_LEGS     = "Leggings",
    INVTYPE_WRIST    = "Bracers",
    INVTYPE_WAIST    = "Belt",
    INVTYPE_FEET     = "Boots",
}

-- ============================================================================
-- Set of all token IDs for the fast IsToken check.
-- ============================================================================

local ALL_TOKEN_IDS = {}
for _, byGroup in pairs(TOKEN_BY_TIER_GROUP_SLOT) do
    for _, bySlot in pairs(byGroup) do
        for _, id in pairs(bySlot) do
            if id then ALL_TOKEN_IDS[id] = true end
        end
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

function Tokens:IsToken(itemID)
    return itemID ~= nil and ALL_TOKEN_IDS[itemID] == true
end

--- Resolve the class-token that redeems for `itemID`. Returns nil for
--- non-set items, items not yet in the WoW client cache, or set/slot
--- combinations that don't have a known token. Returns nil for items in
--- non-tracked classes too (e.g. Death Knight items, if any leak through).
function Tokens:GetTokenFor(itemID)
    if not itemID then return nil end

    local _, _, _, _, _, _, _, _, equipLoc,
          _, _, _, _, _, _, setID = GetItemInfo(itemID)
    if type(setID) ~= "number" or setID <= 0 then return nil end

    local mapping = SET_TO_TIER_CLASS[setID]
    if not mapping then return nil end

    local groupMap = (mapping.tier == "T6") and GROUP_T6 or GROUP_T4_T5
    local group    = groupMap[mapping.class]
    if not group then return nil end

    local slotKey = SLOT_KEY[equipLoc]
    if not slotKey then return nil end

    local tier = TOKEN_BY_TIER_GROUP_SLOT[mapping.tier]
    if not tier or not tier[group] then return nil end
    return tier[group][slotKey]
end

function Tokens:GetSourceTokenLabel(tokenID)
    return Tokens.LABELS[tokenID] or ("Token " .. tostring(tokenID))
end

function Tokens:Initialize()
    -- Nothing to do at load time.
end
