local ADDON_NAME, ns = ...

-- Heal-over-time spells per healing class. Name-only match so it works
-- regardless of rank.
local CLASS_HOT_NAMES = {
    DRUID  = { Rejuvenation = true, Regrowth = true },
    PRIEST = { Renew = true },
    -- Paladin has no HoTs in Classic Era.
    -- Shaman has none in Era either (Riptide is WotLK).
}

-- Spell-ID overrides for HoT procs that should surface with a non-default
-- icon — e.g., the Priest T2 8-piece bonus that grants a Renew, which we
-- want to render with the Greater Heal icon to distinguish it from a
-- self-cast Renew. Use /hh scanbuffs to find the spellID, then add it.
local CLASS_HOT_BY_ID = {
    PRIEST = {
        -- T2 8-piece (Vestments of Transcendence) Renew proc — render with
        -- the Greater Heal icon to distinguish it from a self-cast Renew.
        [22009] = "Interface\\Icons\\Spell_Holy_GreaterHeal",
    },
    DRUID  = {},
}

local getBuff
if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    getBuff = function(unit, i)
        local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name, a.icon, a.sourceUnit, a.spellId, a.expirationTime, a.duration
    end
elseif UnitBuff then
    getBuff = function(unit, i)
        local name, icon, _, _, dur, exp, source, _, _, spellId = UnitBuff(unit, i)
        return name, icon, source, spellId, exp, dur
    end
else
    getBuff = function() return nil end
end

ns.HoTGetBuff = getBuff

-- Returns a list of {name, icon, exp, dur, source} for HoTs on the
-- given unit, scoped to spells the player's class can cast. Includes
-- HoTs cast by anyone — the goal is "is this HoT already running so I
-- don't waste a refresh," which doesn't depend on who cast it. The
-- source field is preserved on each entry so callers can distinguish
-- mine vs. theirs if they want to (e.g. desaturate others' icons).
local function scan(unit)
    local out = {}
    if not unit or not UnitExists(unit) then return out end
    local namedHots = CLASS_HOT_NAMES[ns.playerClass]
    local idHots    = CLASS_HOT_BY_ID[ns.playerClass]
    if not namedHots and not idHots then return out end

    for i = 1, 40 do
        local name, icon, source, spellId, exp, dur = getBuff(unit, i)
        if not name then break end
        if namedHots and namedHots[name] then
            out[#out + 1] = { name = name, icon = icon, exp = exp, dur = dur, source = source }
        elseif idHots and spellId and idHots[spellId] then
            out[#out + 1] = { name = name, icon = idHots[spellId], exp = exp, dur = dur, source = source }
        end
    end
    return out
end

local function paint(button)
    if not button.hotIcons then return end

    local found = scan(button:GetAttribute("unit"))
    -- Assign to icon slots; hide leftover slots.
    for i = 1, #button.hotIcons do
        local slot = button.hotIcons[i]
        if found[i] then
            slot:SetTexture(found[i].icon)
            slot:Show()
        else
            slot:Hide()
        end
    end
end

local function isRelevant(unit)
    if not unit then return false end
    return unit == "player"
        or unit:match("^party%d$")
        or unit:match("^raid%d+$")
        or unit == "pet"
        or unit:match("^partypet%d$")
        or unit:match("^raidpet%d+$")
        or unit == "target"
        or unit == "targettarget"
end

local function onUnitChange(unit)
    if not isRelevant(unit) then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end

ns.HoT = { Paint = paint, Scan = scan }

ns:On("UNIT_AURA", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
