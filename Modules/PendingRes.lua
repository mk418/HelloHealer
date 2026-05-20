local ADDON_NAME, ns = ...

-- Show the standard Blizzard res icon centered on a cell when that
-- player has an incoming resurrection (Rebirth, Soulstone, normal
-- Resurrection — UnitHasIncomingResurrection covers all of them).
-- Cleared automatically when the popup is accepted, declined, or
-- times out via INCOMING_RESURRECT_CHANGED.
--
-- Gated on UnitIsDeadOrGhost because UnitHasIncomingResurrection
-- also returns true for *living* players with a pre-applied rez
-- effect attached (Warlock Soulstone, Shaman Reincarnation) — they
-- aren't being resurrected right now, the effect just stands by for
-- when they next die. Without the dead-check the icon lights up on
-- every soulstoned healer the moment they zone in.
local function paint(button)
    if not button.resIcon then return end
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then
        button.resIcon:Hide()
        return
    end
    if UnitIsDeadOrGhost(unit)
        and UnitHasIncomingResurrection
        and UnitHasIncomingResurrection(unit)
    then
        button.resIcon:Show()
    else
        button.resIcon:Hide()
    end
end

ns.PendingRes = { Paint = paint }

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

ns:On("INCOMING_RESURRECT_CHANGED", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
