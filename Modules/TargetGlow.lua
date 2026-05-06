local ADDON_NAME, ns = ...

-- Soft cyan, low alpha. Stays out of the threat-tier well
-- (yellow/orange/red/purple) and the incoming-heal green, so the glow
-- is unambiguously "this is your current target" at a glance.
local GLOW_COLOR = { 0.4, 0.8, 1.0, 0.45 }

local function setGlow(button, on)
    if not button.targetGlow then return end
    if on then
        for i = 1, #button.targetGlow do
            local t = button.targetGlow[i]
            t:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
            t:Show()
        end
    else
        for i = 1, #button.targetGlow do
            button.targetGlow[i]:Hide()
        end
    end
end

local function paint(button)
    local unit = button:GetAttribute("unit")
    if not unit then setGlow(button, false); return end

    -- Never glow the dedicated Target / ToT cells themselves — those
    -- frames already represent the target. The glow exists to surface
    -- the *group/tank* cell that corresponds to whoever you're
    -- currently targeting.
    if unit == "target" or unit == "targettarget" then
        setGlow(button, false)
        return
    end

    if not UnitExists("target") or not UnitIsUnit(unit, "target") then
        setGlow(button, false)
        return
    end

    setGlow(button, true)
end

ns.TargetGlow = { Paint = paint }

local function paintAll()
    ns.Cell:ForEach(paint)
end

-- Target changes are global: the previously-glowing cell turns off and
-- the new one turns on, so a full sweep is the right granularity.
ns:On("PLAYER_TARGET_CHANGED", paintAll)

-- Skin-triggering events: defer one frame so we paint AFTER Header's
-- skinAll has run. Same dispatcher fires both handlers on these events,
-- but TargetGlow registers at file-load while Header's skinAll
-- registers later inside PLAYER_LOGIN, so the natural order has us
-- running before skinAll. Without the defer, a player who joins while
-- already targeted spawns a fresh cell that never gets paint() called
-- on it. PLAYER_REGEN_ENABLED is here because Header runs a post-combat
-- catch-up skin on that event for cells whose spawn was deferred during
-- combat lockdown.
local function deferredPaintAll()
    C_Timer.After(0, paintAll)
end
ns:On("GROUP_ROSTER_UPDATE",   deferredPaintAll)
ns:On("PLAYER_ENTERING_WORLD", deferredPaintAll)
ns:On("PLAYER_REGEN_ENABLED",  deferredPaintAll)
