local ADDON_NAME, ns = ...

-- Power type → color. Mirrors PowerBarColor where possible but kept explicit
-- so we don't depend on it.
local POWER_COLORS = {
    [0] = { 0.31, 0.45, 0.63 }, -- Mana
    [1] = { 0.78, 0.25, 0.25 }, -- Rage
    [2] = { 1.00, 0.50, 0.25 }, -- Focus
    [3] = { 1.00, 1.00, 0.00 }, -- Energy
    [6] = { 0.00, 0.82, 1.00 }, -- Runic Power (not in Era but harmless)
}

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit or not button.powerBar then return end

    local powerType = UnitPowerType(unit)
    local cur, max = UnitPower(unit), UnitPowerMax(unit)

    if not max or max <= 0 then
        button.powerBar:SetValue(0)
        return
    end

    button.powerBar:SetMinMaxValues(0, max)
    button.powerBar:SetValue(cur)

    local c = POWER_COLORS[powerType] or { 0.5, 0.5, 0.5 }
    button.powerBar:SetStatusBarColor(c[1], c[2], c[3])
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

ns.Power = { Paint = paint }

ns:On("UNIT_POWER_UPDATE",   onUnitChange)
ns:On("UNIT_MAXPOWER",       onUnitChange)
ns:On("UNIT_DISPLAYPOWER",   onUnitChange)

-- Initial paint pass when frames first appear / roster changes
local function paintAll()
    ns.Cell:ForEach(paint)
end
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
