local ADDON_NAME, ns = ...

local HealComm = LibStub and LibStub("LibHealComm-4.0", true)
if not HealComm then
    ns.IncomingHeal = { Paint = function() end }
    return
end

local ALL_HEALS = HealComm.ALL_HEALS or 0xF

local function paint(button)
    if not button.incomingBar then return end
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        button.incomingBar:SetValue(0)
        return
    end
    local guid = UnitGUID(unit)
    if not guid then
        button.incomingBar:SetValue(0)
        return
    end

    local incoming = HealComm:GetHealAmount(guid, ALL_HEALS) or 0
    local mod = HealComm:GetHealModifier(guid) or 1
    incoming = incoming * mod

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if not hpMax or hpMax <= 0 then
        button.incomingBar:SetValue(0)
        return
    end
    local total = hp + incoming
    if total > hpMax then total = hpMax end
    button.incomingBar:SetValue(total / hpMax)
end

ns.IncomingHeal = { Paint = paint }

local function paintAll()
    ns.Cell:ForEach(paint)
end

local function paintByGUIDs(...)
    local n = select("#", ...)
    if n == 0 then return end
    local set = {}
    for i = 1, n do set[select(i, ...)] = true end
    ns.Cell:ForEach(function(button)
        local unit = button:GetAttribute("unit")
        if unit and UnitExists(unit) and set[UnitGUID(unit)] then
            paint(button)
        end
    end)
end

local listener = {}

-- HealStarted/Updated/Delayed/Stopped fire with target GUIDs as varargs
-- after a fixed prefix. Stopped has an extra `interrupted` flag at
-- position 5; the rest put GUIDs starting at position 5.
local function onHealEvent(event, casterGUID, spellID, healType, endTime, ...)
    paintByGUIDs(...)
end

local function onHealStopped(event, casterGUID, spellID, healType, interrupted, ...)
    paintByGUIDs(...)
end

local function onModifierChanged(event, targetGUID)
    paintByGUIDs(targetGUID)
end

HealComm.RegisterCallback(listener, "HealComm_HealStarted",     onHealEvent)
HealComm.RegisterCallback(listener, "HealComm_HealUpdated",     onHealEvent)
HealComm.RegisterCallback(listener, "HealComm_HealDelayed",     onHealEvent)
HealComm.RegisterCallback(listener, "HealComm_HealStopped",     onHealStopped)
HealComm.RegisterCallback(listener, "HealComm_ModifierChanged", onModifierChanged)
HealComm.RegisterCallback(listener, "HealComm_GUIDDisappeared", onModifierChanged)

local function onUnitChange(unit)
    if not unit then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end
ns:On("UNIT_HEALTH",    onUnitChange)
ns:On("UNIT_MAXHEALTH", onUnitChange)
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
