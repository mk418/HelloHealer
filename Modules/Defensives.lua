local ADDON_NAME, ns = ...

-- Active defensive cooldowns to surface. Keyed by class so the per-cell
-- scan only walks buffs whose name matches a class-relevant defensive.
-- "Defensive" here is broad: any tank-survivability button — pure
-- damage-reduction, immunity, emergency healing — all qualify.
-- Extend by adding entries; the format is { name = ... }.
local DEFENSIVES = {
    WARRIOR = {
        { name = "Shield Wall" },
        { name = "Last Stand" },
        { name = "Shield Block" },
    },
    DRUID = {
        { name = "Barkskin" },
        { name = "Frenzied Regeneration" },
    },
    PALADIN = {
        { name = "Divine Shield" },
        { name = "Divine Protection" },
    },
}

-- Build a flat name → true lookup for fast per-buff filtering. We don't
-- key by class on the lookup side because the player wants to see ANY
-- defensive on ANY unit (e.g., a Paladin DPS popping Divine Shield is
-- worth surfacing on their cell and in their tooltip).
local NAME_LOOKUP = {}
for _, list in pairs(DEFENSIVES) do
    for _, def in ipairs(list) do
        NAME_LOOKUP[def.name] = true
    end
end

local getBuff
if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    getBuff = function(unit, i)
        local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name, a.icon, a.expirationTime, a.duration
    end
elseif UnitBuff then
    getBuff = function(unit, i)
        local name, icon, _, _, dur, exp = UnitBuff(unit, i)
        return name, icon, exp, dur
    end
else
    getBuff = function() return nil end
end

-- Returns a list of { name, icon, exp, dur } for active defensives on
-- the given unit. Shared by the cell painter and Cell.lua's tooltip.
local function scan(unit)
    local out = {}
    if not unit or not UnitExists(unit) then return out end
    for i = 1, 40 do
        local name, icon, exp, dur = getBuff(unit, i)
        if not name then break end
        if NAME_LOOKUP[name] then
            out[#out + 1] = { name = name, icon = icon, exp = exp, dur = dur }
        end
    end
    return out
end

-- Tank cells live under ns.TankHeader.frame; group cells under
-- ns.Header.frame. Defensive overlay is tank-specific per DESIGN. The
-- tooltip section in Cell.lua does not gate on this — it surfaces
-- defensives for any cell.
local function isTankCell(button)
    if not ns.TankHeader or not ns.TankHeader.frame then return false end
    return button:GetParent() == ns.TankHeader.frame
end

local function paint(button)
    if not button.defensiveIcons then return end
    local function hideAll()
        for i = 1, #button.defensiveIcons do button.defensiveIcons[i]:Hide() end
    end

    if not isTankCell(button) then hideAll() return end

    local found = scan(button:GetAttribute("unit"))
    for i = 1, #button.defensiveIcons do
        local slot = button.defensiveIcons[i]
        local f = found[i]
        if f then
            slot.icon:SetTexture(f.icon)
            if f.dur and f.dur > 0 and f.exp and f.exp > 0 then
                slot.cooldown:SetCooldown(f.exp - f.dur, f.dur)
            else
                slot.cooldown:Clear()
            end
            slot:Show()
        else
            slot:Hide()
        end
    end
end

ns.Defensives = { Paint = paint, Scan = scan }

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

ns:On("UNIT_AURA", onUnitChange)

local function paintAll()
    ns.Cell:ForEach(paint)
end

-- Skin-triggering events: defer one frame so we paint AFTER Header's
-- skinAll (same registration-order issue as Modules/TargetGlow.lua —
-- see that file's comment for the full explanation).
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)
