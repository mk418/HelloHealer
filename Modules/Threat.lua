local ADDON_NAME, ns = ...

-- UnitThreatSituation(unit) returns 0..3:
--   0 = lower threat than the current tank
--   1 = higher threat than tank but not actively tanked
--   2 = tanking, but threat lead is contested (could lose aggro)
--   3 = securely tanking (threat well above #2)
--
-- Healer-facing meaning differs for tanks vs non-tanks: for a non-tank,
-- a rising number is bad (1=warning, 3=mob is on them). For a tank, 3 is
-- the "I am holding aggro" state — surfaced as purple so the healer can
-- see at a glance which tank currently has the boss; a falling number
-- from 3 is the warning gradient (yellow → orange → red).

local NON_TANK_COLORS = {
    [1] = { 1.0, 1.0, 0.0 }, -- yellow: above tank, no aggro yet
    [2] = { 1.0, 0.5, 0.0 }, -- orange: tanking but contested
    [3] = { 1.0, 0.0, 0.0 }, -- red: firmly aggroed
}

local TANK_COLORS = {
    [3] = { 0.6, 0.2, 0.85 }, -- purple: holding aggro firmly
    [2] = { 1.0, 1.0, 0.0 },  -- yellow: lead is slipping
    [1] = { 1.0, 0.5, 0.0 },  -- orange: lost the lead
    [0] = { 1.0, 0.0, 0.0 },  -- red: not on the threat list at all
}

local function isAssignedTank(unit)
    if UnitGroupRolesAssigned then
        local role = UnitGroupRolesAssigned(unit)
        if role == "TANK" then return true end
    end
    if IsInRaid() and GetPartyAssignment then
        if GetPartyAssignment("MAINTANK", unit) then return true end
    end
    return false
end

local function colorFor(unit)
    local status = UnitThreatSituation(unit)
    if not status then return nil end
    if isAssignedTank(unit) then
        return TANK_COLORS[status]
    end
    if status > 0 then
        return NON_TANK_COLORS[status]
    end
    return nil
end

local function setBorder(button, color)
    if not button.threatBorder then return end
    if color then
        for i = 1, #button.threatBorder do
            local t = button.threatBorder[i]
            t:SetVertexColor(color[1], color[2], color[3], 1)
            t:Show()
        end
    else
        for i = 1, #button.threatBorder do
            button.threatBorder[i]:Hide()
        end
    end
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        setBorder(button, nil)
        return
    end
    -- Suppress entirely outside combat to avoid painting tanks red just
    -- because they aren't actively engaged.
    if not InCombatLockdown() and not UnitAffectingCombat("player") then
        setBorder(button, nil)
        return
    end
    setBorder(button, colorFor(unit))
end

ns.Threat = { Paint = paint }

local function isRelevant(unit)
    if not unit then return false end
    return unit == "player"
        or unit:match("^party%d$")
        or unit:match("^raid%d+$")
        or unit == "target"
        or unit == "targettarget"
end

local function onUnitChange(unit)
    if not isRelevant(unit) then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end

ns:On("UNIT_THREAT_LIST_UPDATE",      onUnitChange)
ns:On("UNIT_THREAT_SITUATION_UPDATE", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end
ns:On("PLAYER_REGEN_DISABLED", paintAll)
ns:On("PLAYER_REGEN_ENABLED",  paintAll)
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
