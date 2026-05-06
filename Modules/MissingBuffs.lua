local ADDON_NAME, ns = ...

-- Tracks raid buffs the player's class is responsible for casting.
-- Surfaces an amber outer glow on any group/tank cell that is missing
-- one of those buffs, plus a "Missing buffs:" line in the cell tooltip
-- listing what's missing. Class-scoped so a Priest never sees a Mark
-- alert (they can't cast it) and a Druid never sees a Fortitude alert.
-- The category model treats short/long versions as equivalent — Prayer
-- of Fortitude satisfies the Fortitude category, Gift of the Wild
-- satisfies the Mark category.

local CATEGORIES = {
    PRIEST = {
        { name = "Fortitude",
          auras = { "Power Word: Fortitude", "Prayer of Fortitude" } },
        { name = "Spirit",
          auras = { "Divine Spirit", "Prayer of Spirit" } },
    },
    DRUID = {
        { name = "Mark of the Wild",
          auras = { "Mark of the Wild", "Gift of the Wild" } },
    },
    -- Paladin / Shaman not listed: Paladins use Blessings (already
    -- in CooldownTrack), Shamans don't have a passive raid buff in
    -- Classic Era. Priests / Druids only by design — keeps the at-a-
    -- glance signal actionable for the viewer.
}

-- Solid amber for the left-edge indicator bar. Higher alpha than the
-- previous additive wash since this is a small fixed strip and needs
-- to read clearly from across a 40-man frame.
local GLOW_COLOR = { 1.0, 0.65, 0.15, 0.95 }

local getBuff
if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    getBuff = function(unit, i)
        local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name
    end
elseif UnitBuff then
    getBuff = function(unit, i)
        return (UnitBuff(unit, i))
    end
else
    getBuff = function() return nil end
end

-- Returns a list of category names (e.g. {"Fortitude", "Spirit"}) that
-- the unit is missing relative to the player's class buff list.
-- Empty list = nothing missing. Shared with Cell.lua's tooltip.
local function scan(unit)
    local cats = CATEGORIES[ns.playerClass]
    if not cats or not unit or not UnitExists(unit) then return {} end

    local present = {}
    for i = 1, 40 do
        local name = getBuff(unit, i)
        if not name then break end
        present[name] = true
    end

    local missing = {}
    for _, cat in ipairs(cats) do
        local has = false
        for _, auraName in ipairs(cat.auras) do
            if present[auraName] then has = true; break end
        end
        if not has then missing[#missing + 1] = cat.name end
    end
    return missing
end

local function setGlow(button, on)
    if not button.missingBuffGlow then return end
    if on then
        for i = 1, #button.missingBuffGlow do
            local t = button.missingBuffGlow[i]
            t:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            t:Show()
        end
    else
        for i = 1, #button.missingBuffGlow do
            button.missingBuffGlow[i]:Hide()
        end
    end
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit then setGlow(button, false); return end

    -- Skip the dedicated Target / ToT cells. Their unit attribute can
    -- hop to enemies, pets, NPCs, etc., which would falsely glow the
    -- frame; the buff alert is meant for the stable group/tank cells.
    if unit == "target" or unit == "targettarget" then
        setGlow(button, false)
        return
    end

    -- Pets / NPCs in raid don't get raid buffs — skip them so we don't
    -- light up the Hunter pet cell that the secure header may include.
    if not UnitIsPlayer(unit) then setGlow(button, false); return end

    -- Offline players can't be buffed; suppress the alert until they
    -- come back online (otherwise the cell would glow indefinitely).
    if UnitIsConnected(unit) == false then setGlow(button, false); return end

    local missing = scan(unit)
    setGlow(button, #missing > 0)
end

ns.MissingBuffs = { Paint = paint, Scan = scan }

local function isRelevant(unit)
    if not unit then return false end
    return unit == "player"
        or unit:match("^party%d$")
        or unit:match("^raid%d+$")
end

local function onUnitChange(unit)
    if not isRelevant(unit) then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end

ns:On("UNIT_AURA",       onUnitChange)
ns:On("UNIT_CONNECTION", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end

-- Same defer-after-skinAll pattern as TargetGlow / Defensives — see
-- Modules/TargetGlow.lua for the full explanation of why these three
-- skin-triggering events need a one-frame deferral.
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)
