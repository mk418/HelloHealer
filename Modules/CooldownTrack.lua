local ADDON_NAME, ns = ...

-- Per-class auras to track on each cell with a cooldown swipe.
-- "filter" determines whether we look at buffs (HELPFUL) or debuffs
-- (HARMFUL). Add entries here to extend tracking.
-- Power Word: Shield is in every healer's list so any healer can see at
-- a glance who's already shielded — the absorb makes a difference for
-- triage decisions regardless of what class the viewer plays. For the
-- shielding Priest specifically, having both PW:S and Weakened Soul in
-- the same row pairs the "shield up" and "can't re-shield until" data.
local TRACKED = {
    PRIEST = {
        { name = "Power Word: Shield", filter = "HELPFUL" },
        { name = "Weakened Soul",      filter = "HARMFUL" },
        { name = "Power Infusion",     filter = "HELPFUL" },
    },
    DRUID = {
        { name = "Power Word: Shield", filter = "HELPFUL" },
        { name = "Innervate",          filter = "HELPFUL" },
    },
    PALADIN = {
        { name = "Power Word: Shield",     filter = "HELPFUL" },
        { name = "Forbearance",            filter = "HARMFUL" },
        { name = "Blessing of Protection", filter = "HELPFUL" },
    },
    SHAMAN = {},
}

local getBuff, getDebuff
if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    getBuff = function(unit, i)
        local a = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name, a.icon, a.expirationTime, a.duration
    end
    getDebuff = function(unit, i)
        local a = C_UnitAuras.GetDebuffDataByIndex(unit, i)
        if not a then return nil end
        return a.name, a.icon, a.expirationTime, a.duration
    end
elseif UnitBuff then
    getBuff = function(unit, i)
        local name, icon, _, _, dur, exp = UnitBuff(unit, i)
        return name, icon, exp, dur
    end
    getDebuff = function(unit, i)
        local name, icon, _, _, dur, exp = UnitDebuff(unit, i)
        return name, icon, exp, dur
    end
else
    getBuff   = function() return nil end
    getDebuff = function() return nil end
end

local function findAura(unit, target)
    local fn = (target.filter == "HARMFUL") and getDebuff or getBuff
    for i = 1, 40 do
        local name, icon, exp, dur = fn(unit, i)
        if not name then return nil end
        if name == target.name then
            return icon, exp, dur
        end
    end
end

-- Returns a list of { name, icon, exp, dur, filter } for tracked auras
-- currently active on the unit, in the order they appear in TRACKED for
-- the player's class. Shared by paint() and Cell.lua's tooltip so the
-- bottom-left icon row and the tooltip "Tracked:" section stay in sync.
local function scan(unit)
    local out = {}
    if not unit or not UnitExists(unit) then return out end
    local list = TRACKED[ns.playerClass]
    if not list or #list == 0 then return out end
    for _, t in ipairs(list) do
        local icon, exp, dur = findAura(unit, t)
        if icon then
            out[#out + 1] = { name = t.name, icon = icon, exp = exp, dur = dur, filter = t.filter }
        end
    end
    return out
end

local function paint(button)
    if not button.cdIcons then return end
    local function hideAll()
        for i = 1, #button.cdIcons do button.cdIcons[i]:Hide() end
    end

    local found = scan(button:GetAttribute("unit"))
    if #found == 0 then hideAll() return end

    for i = 1, #button.cdIcons do
        local slot = button.cdIcons[i]
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

ns.CooldownTrack = { Paint = paint, Scan = scan }

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
ns:On("PLAYER_ENTERING_WORLD", paintAll)
ns:On("GROUP_ROSTER_UPDATE",   paintAll)
