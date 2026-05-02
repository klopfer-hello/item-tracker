--[[
    Klopfer's Item Tracker - Theme Module
    Single Responsibility: Canonical dark/gold palette and the small set
    of frame helpers (manual background + border) every UI module shares,
    so the whole addon reads as a single visual identity.

    Loaded right after Core.lua, before any UI module — modules pick up
    the table by reference (`local P = IT.Theme.P`), so live edits to
    the palette propagate addon-wide on /reload.

    No BackdropTemplate anywhere: every panel uses AddBackground for the
    fill and AddBorder for the 1px frame edges. Keeps frame nesting
    consistent and avoids the Blizzard backdrop-edge artifacts we hit
    earlier.
]]

local _, IT = ...
local Theme = {}
IT.Theme = Theme

-- ============================================================================
-- Palette
-- Keep this the only place colours are defined. Adding a new shade? Add
-- it here, never inline a magic RGB elsewhere.
-- ============================================================================

Theme.P = {
    bg          = { 0.04, 0.04, 0.06, 1.00 },     -- main backdrop (opaque)
    surface     = { 0.08, 0.08, 0.11, 1.00 },     -- panels
    surfaceAlt  = { 0.12, 0.12, 0.15, 1.00 },     -- alt rows / pills
    bgHi        = { 0.18, 0.14, 0.05, 1.00 },     -- hover tint for accent buttons
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

-- ============================================================================
-- Helpers
-- ============================================================================

function Theme.SetColor(tex, c)
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

function Theme.AddBackground(parent, color)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    Theme.SetColor(bg, color)
    return bg
end

--- Draw a 1px (or `thickness`-px) border around `parent` using four edge
--- textures. Replaces the BackdropTemplate edge artwork; works on any
--- frame regardless of strata / template. Returns an array of the four
--- edge textures so callers can recolour or hide them later (used for
--- the active-loadout swatch highlight in GearGoalsUI).
function Theme.AddBorder(parent, c, thickness)
    thickness = thickness or 1
    local edges = {}
    for _, p in ipairs({
        { "TOPLEFT",    "TOPRIGHT",    nil,       thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil,       thickness },
        { "TOPLEFT",    "BOTTOMLEFT",  thickness, nil       },
        { "TOPRIGHT",   "BOTTOMRIGHT", thickness, nil       },
    }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p[1]); t:SetPoint(p[2])
        if p[3] then t:SetWidth(p[3])  end
        if p[4] then t:SetHeight(p[4]) end
        Theme.SetColor(t, c)
        table.insert(edges, t)
    end
    return edges
end

-- ============================================================================
-- Module Interface (no Initialize needed — pure data + helpers)
-- ============================================================================

-- Theme is consumed at file-load time via `local P = IT.Theme.P`, so it
-- has no Initialize hook. Loaded order is enforced by the TOC: Theme.lua
-- comes right after Core.lua, before any UI module.
