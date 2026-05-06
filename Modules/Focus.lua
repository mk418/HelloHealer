local ADDON_NAME, ns = ...

-- Per-character focus list — surfaces 1-N raid healing assignments by
-- glowing the assigned players' existing group/tank cells. Stored in
-- HelloHealerCharDB.focusList; managed via /hh focus, /hh unfocus,
-- /hh focuses, /hh focus clear (see Core.lua).

-- Bright pink, additive blend. Distinct from the cyan target glow
-- (Modules/TargetGlow.lua), the threat-tier border palette
-- (yellow/orange/red/purple), the incoming-heal green segment, and the
-- amber missing-buffs left bar. Slightly higher alpha than the target
-- glow because focus is a deliberate assignment rather than transient
-- state.
local GLOW_COLOR = { 1.0, 0.3, 0.8, 0.55 }

local function focusList()
    return HelloHealerCharDB and HelloHealerCharDB.focusList or nil
end

local function isFocused(name)
    if not name then return false end
    local list = focusList()
    if not list or #list == 0 then return false end
    local lower = name:lower()
    for i = 1, #list do
        if list[i]:lower() == lower then return true end
    end
    return false
end

local function setGlow(button, on)
    if not button.focusGlow then return end
    if on then
        for i = 1, #button.focusGlow do
            local t = button.focusGlow[i]
            t:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            t:Show()
        end
    else
        for i = 1, #button.focusGlow do
            button.focusGlow[i]:Hide()
        end
    end
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit then setGlow(button, false); return end

    -- Skip Target/ToT cells: their unit attribute hops to whoever is
    -- currently targeted, including enemies/NPCs. Focus is a property
    -- of a stable group/tank cell — same reasoning as TargetGlow.
    if unit == "target" or unit == "targettarget" then
        setGlow(button, false)
        return
    end

    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        setGlow(button, false)
        return
    end

    local name, realm = UnitName(unit)
    if not name then setGlow(button, false); return end

    if isFocused(name) then setGlow(button, true); return end
    if realm and realm ~= "" and isFocused(name .. "-" .. realm) then
        setGlow(button, true); return
    end
    setGlow(button, false)
end

local function paintAll()
    ns.Cell:ForEach(paint)
end

ns.Focus = { Paint = paint, RepaintAll = paintAll }

-- Same defer-after-skinAll pattern as TargetGlow / MissingBuffs — these
-- skin-triggering events fire before our handler order would naturally
-- catch newly-spawned cells, so we wait one frame for skinAll to finish.
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)

ns:On("UNIT_NAME_UPDATE", function(unit)
    if not unit then return end
    ns.Cell:ForEachCellForUnit(unit, paint)
end)
