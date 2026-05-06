local ADDON_NAME, ns = ...

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
    ns.Cell:UpdateUnit(unit)
end

ns:On("UNIT_HEALTH",     onUnitChange)
ns:On("UNIT_MAXHEALTH",  onUnitChange)
ns:On("UNIT_CONNECTION", onUnitChange)
