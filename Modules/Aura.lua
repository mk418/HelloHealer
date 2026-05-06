local ADDON_NAME, ns = ...

local CLASS_DISPELS = {
    PRIEST  = { Magic = true, Disease = true },
    DRUID   = { Curse = true, Poison = true },
    PALADIN = { Magic = true, Disease = true, Poison = true },
    SHAMAN  = { Disease = true, Poison = true },
}

ns.Aura = ns.Aura or {}
ns.Aura.CLASS_DISPELS = CLASS_DISPELS

local function priorityOf(debuffType)
    local list = HelloHealerDB.classDispelPriority[ns.playerClass]
    if not list then return 999 end
    for i = 1, #list do
        if list[i] == debuffType then return i end
    end
    return 999
end

-- Wrapper signature: name, icon, count, dispelType, exp, dur. The
-- legacy UnitDebuff API returns (..., dur, exp, ...) — note the order
-- is duration-then-expiration; we swap to match the modern path so
-- callers (Aura.paint, Cell.lua tooltip) get a consistent shape.
local getDebuff
if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
    getDebuff = function(unit, i)
        local a = C_UnitAuras.GetDebuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name, a.icon, a.applications, a.dispelName, a.expirationTime, a.duration
    end
elseif UnitDebuff then
    getDebuff = function(unit, i)
        local name, icon, count, dt, dur, exp = UnitDebuff(unit, i)
        return name, icon, count, dt, exp, dur
    end
else
    getDebuff = function() return nil end
end

ns.Aura = ns.Aura or {}
ns.Aura.getDebuff = getDebuff

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit or not button.debuffIcons then return end

    local function hideAll()
        for i = 1, #button.debuffIcons do button.debuffIcons[i]:Hide() end
    end

    local canDispel = CLASS_DISPELS[ns.playerClass]
    if not canDispel then hideAll() return end

    local matches = {}
    for i = 1, 40 do
        local name, icon, _, debuffType = getDebuff(unit, i)
        if not name then break end
        if debuffType and canDispel[debuffType] then
            matches[#matches + 1] = { icon = icon, prio = priorityOf(debuffType) }
        end
    end

    -- Stable sort by class priority (lower index = higher priority).
    -- The priority list isn't user-configurable, but it still gives the
    -- icons a deterministic order so they don't visually shuffle as
    -- new debuffs land — your eye can rely on "leftmost icon = the
    -- school I should care about most."
    table.sort(matches, function(a, b) return a.prio < b.prio end)

    for i = 1, #button.debuffIcons do
        local slot = button.debuffIcons[i]
        local m = matches[i]
        if m then
            slot:SetTexture(m.icon)
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

ns.Aura.Paint = paint

ns:On("UNIT_AURA", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
