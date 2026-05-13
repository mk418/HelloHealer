local ADDON_NAME, ns = ...

-- Per-character subgroup highlight — glows every cell whose raid
-- subgroup is flagged in HelloHealerCharDB.highlightSubgroups. Used
-- mid-raid to focus on whichever group(s) a healer is assigned to.
-- Managed via /hh highlight, /hh highlights (see Core.lua).
--
-- Membership follows the player: a player who swaps subgroups during
-- the fight loses/gains the glow on the next GROUP_ROSTER_UPDATE,
-- which is what makes this preferable to a name-based assignment.

-- Saturated blue, additive blend. Distinct from cyan target glow,
-- pink focus glow, white triage glow, amber missing-buffs bar, and
-- the threat-tier border palette.
local GLOW_COLOR = { 0.2, 0.5, 1.0, 0.55 }

local function highlightSet()
    return HelloHealerCharDB and HelloHealerCharDB.highlightSubgroups or nil
end

local function setGlow(button, on)
    if not button.subgroupGlow then return end
    if on then
        for i = 1, #button.subgroupGlow do
            local t = button.subgroupGlow[i]
            t:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            t:Show()
        end
    else
        for i = 1, #button.subgroupGlow do
            button.subgroupGlow[i]:Hide()
        end
    end
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit then setGlow(button, false); return end

    -- Skip Target/ToT cells: their unit attribute hops to whoever is
    -- currently targeted, including enemies/NPCs. Highlight is a
    -- property of a stable group/tank cell — same reasoning as Focus.
    if unit == "target" or unit == "targettarget" then
        setGlow(button, false)
        return
    end

    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        setGlow(button, false)
        return
    end

    local set = highlightSet()
    if not set or not next(set) then setGlow(button, false); return end

    local sg = ns.Cell.UnitSubgroup(unit)
    setGlow(button, sg ~= nil and set[sg] == true)
end

local function paintAll()
    ns.Cell:ForEach(paint)
end

ns.SubgroupHighlight = { Paint = paint, RepaintAll = paintAll }

-- Same defer-after-skinAll pattern as Focus / TargetGlow / MissingBuffs:
-- the skin-triggering events fire before our handler order would
-- naturally catch newly-spawned cells, so we wait one frame for
-- skinAll to finish. GROUP_ROSTER_UPDATE is the key event — it's the
-- one that fires on subgroup moves, so the highlight follows players
-- around without any extra bookkeeping.
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)
