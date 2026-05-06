local ADDON_NAME, ns = ...

-- Range-check spell per class. All three pick a 40yd healing spell so the
-- fade behavior is consistent across Priest/Druid/Paladin.
local RANGE_SPELL = {
    PRIEST  = "Flash Heal",
    DRUID   = "Healing Touch",
    PALADIN = "Holy Light",
    SHAMAN  = "Healing Wave",
}

local IN_ALPHA  = 1.0
local OUT_ALPHA = 0.4

local function inRange(unit)
    if UnitIsUnit(unit, "player") then return true end
    if not UnitIsVisible(unit) then return false end

    local spell = RANGE_SPELL[ns.playerClass]
    if spell then
        local res = IsSpellInRange(spell, unit)
        if res == 1 then return true end
        if res == 0 then return false end
    end
    -- Fallback: Blizzard's default range check (~28yd).
    return UnitInRange(unit) ~= false
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end
    button:SetAlpha(inRange(unit) and IN_ALPHA or OUT_ALPHA)
end

local ticker
local function start()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.2, function()
        ns.Cell:ForEach(paint)
    end)
end

ns.Range = { Paint = paint }

ns:On("PLAYER_ENTERING_WORLD", start)
