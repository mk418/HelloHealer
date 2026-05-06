local ADDON_NAME, ns = ...

-- Triage indicator: bright white outer-ring glow on cells whose
-- predicted post-heals HP fraction is below TRIAGE_THRESHOLD.
-- "Predicted" = current HP + sum of all incoming heals from
-- LibHealComm * heal modifier — same prediction model as
-- IncomingHeal.lua, so HoTs and casts in flight are factored in. This
-- means the indicator suppresses itself when other healers already
-- have the gap covered.
--
-- If LibHealComm isn't loaded the rule degrades to "current HP frac
-- < threshold," which is still useful — you just don't get the
-- already-being-healed suppression.

local TRIAGE_THRESHOLD = 0.50

-- Pure white, additive, high alpha — overpowers the underlying
-- target (cyan) / focus (pink) glows when stacked, so the white reads
-- as the dominant "heal NOW" signal regardless of what else is on
-- the cell.
local GLOW_COLOR = { 1.0, 1.0, 1.0, 0.85 }

local HealComm = LibStub and LibStub("LibHealComm-4.0", true)
local ALL_HEALS = HealComm and HealComm.ALL_HEALS or 0xF

local function predictedFraction(unit)
    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if not hpMax or hpMax <= 0 then return 1 end
    if not HealComm then return hp / hpMax end
    local guid = UnitGUID(unit)
    if not guid then return hp / hpMax end
    local incoming = HealComm:GetHealAmount(guid, ALL_HEALS) or 0
    local mod = HealComm:GetHealModifier(guid) or 1
    return (hp + incoming * mod) / hpMax
end

local function setGlow(button, on)
    if not button.triageGlow then return end
    if on then
        for i = 1, #button.triageGlow do
            local t = button.triageGlow[i]
            t:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            t:Show()
        end
    else
        for i = 1, #button.triageGlow do
            button.triageGlow[i]:Hide()
        end
    end
end

local function isEnabled()
    return HelloHealerCharDB == nil or HelloHealerCharDB.triageEnabled ~= false
end

local function paint(button)
    if not isEnabled() then setGlow(button, false); return end

    local unit = button:GetAttribute("unit")
    if not unit then setGlow(button, false); return end

    -- Skip Target/ToT cells — their unit attribute hops to whatever
    -- you click, including enemies/NPCs that we shouldn't be running
    -- the triage rule against. Same reasoning as TargetGlow / Focus.
    if unit == "target" or unit == "targettarget" then
        setGlow(button, false)
        return
    end

    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        setGlow(button, false)
        return
    end

    -- Dead/ghost: not "in danger of dying" any more — they're already
    -- gone. Resurrection is a different signal handled by PendingRes.
    -- Offline: can't be healed, no point flashing.
    if UnitIsDeadOrGhost(unit) or UnitIsConnected(unit) == false then
        setGlow(button, false)
        return
    end

    setGlow(button, predictedFraction(unit) < TRIAGE_THRESHOLD)
end

local function paintAll()
    ns.Cell:ForEach(paint)
end

ns.Triage = { Paint = paint, RepaintAll = paintAll }

function ns.Triage:IsEnabled()
    return isEnabled()
end

-- Single source of truth for the on/off flip — both the slash command
-- and the settings checkbox call here so they stay in sync. SetChecked
-- on a CheckButton doesn't fire OnClick, so the settings refresh
-- below won't recurse back into SetEnabled.
function ns.Triage:SetEnabled(on)
    if HelloHealerCharDB == nil then return end
    HelloHealerCharDB.triageEnabled = on and true or false
    paintAll()
    if ns.Settings and ns.Settings.RefreshTriageCheckbox then
        ns.Settings:RefreshTriageCheckbox()
    end
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

-- LibHealComm callback wiring matches IncomingHeal.lua. HealStarted /
-- Updated / Delayed put GUIDs as varargs at position 5; Stopped has an
-- extra `interrupted` flag at 5 then GUIDs from 6.
if HealComm then
    local listener = {}
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
end

local function onUnitChange(unit)
    if not unit then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end
ns:On("UNIT_HEALTH",     onUnitChange)
ns:On("UNIT_MAXHEALTH",  onUnitChange)
ns:On("UNIT_CONNECTION", onUnitChange)

-- Same defer-after-skinAll pattern as TargetGlow / Focus / MissingBuffs.
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)
