local ADDON_NAME, ns = ...

ns.ClickCast = {}
local CC = ns.ClickCast

local pendingButtons = {}
local appliedAttrs = {}  -- per-button list of attribute names we set

local function clearAppliedAttrs(button)
    local list = appliedAttrs[button]
    if not list then return end
    for _, attrName in ipairs(list) do
        button:SetAttribute(attrName, nil)
    end
    appliedAttrs[button] = nil
end

-- The cell's unit level drives per-target buff downranking. Only the
-- stable group/player units have a level worth baking against; alias
-- cells (target / targettarget) re-point constantly and aren't re-baked
-- on every swap, so we leave their rank to plain Resolve and let the
-- target cell's own ApplyBindings path handle @target downranking.
local function targetLevelFor(unit)
    if not unit then return nil end
    if unit == "player" or unit:match("^party%d$") or unit:match("^raid%d+$") then
        if UnitExists(unit) then return UnitLevel(unit) end
    end
    return nil
end

local function applyNow(button)
    local bindings = ns.Bindings and ns.Bindings:Get()
    if not bindings then return end

    -- Wipe previously-set click attributes so removed bindings don't
    -- linger on the cell.
    clearAppliedAttrs(button)
    local level = targetLevelFor(button:GetAttribute("unit"))
    local attrs = {}
    for i = 1, #bindings do
        local b = bindings[i]
        -- Skip bindings whose spell the character doesn't know — leaving
        -- a click bound to an unknown spell silently fails on click,
        -- which is confusing. The tooltip surfaces unknown ones in red
        -- so the user can see they're unbindable. Bindings:Resolve also
        -- degrades a missing-rank stored name (e.g. "Healing Wave(Rank
        -- 6)" on a level-30 shaman) to the highest known rank, so
        -- leveling characters get a working click instead of a silent
        -- skip; the tooltip flags any fallback in yellow.
        -- ResolveForTarget additionally downranks scaling buffs to the
        -- highest rank this cell's unit is high enough to receive, so
        -- Fortitude on a low-level group member lands instead of
        -- erroring. With a nil level it is identical to Resolve.
        local resolved = ns.Bindings:ResolveForTarget(b.spell, level)
        if resolved then
            local prefix = (b.mod ~= "" and (b.mod .. "-")) or ""
            local typeAttr  = prefix .. "type" .. b.btn
            local macroAttr = prefix .. "macrotext" .. b.btn
            -- type=macro with [@mouseover] gives a clean "Out of range" failure
            -- and no pending cursor cast. type=spell goes pending instead.
            button:SetAttribute(typeAttr,  "macro")
            button:SetAttribute(macroAttr, "/cast [@mouseover, exists, help] " .. resolved)
            table.insert(attrs, typeAttr)
            table.insert(attrs, macroAttr)
        end
    end
    appliedAttrs[button] = attrs
end

function CC:ApplyTo(button)
    if InCombatLockdown() then
        pendingButtons[button] = true
        return
    end
    applyNow(button)
end

-- Re-apply current bindings to every cell. Called by Bindings slash
-- commands after the user changes a binding so the new spell is
-- live-cast on next click without needing a reload.
function CC:ApplyAll()
    if InCombatLockdown() then
        -- Mark every known cell as pending; PLAYER_REGEN_ENABLED below
        -- will catch up when combat ends.
        if ns.Cell and ns.Cell.ForEach then
            ns.Cell:ForEach(function(b) pendingButtons[b] = true end)
        end
        return
    end
    if ns.Cell and ns.Cell.ForEach then
        ns.Cell:ForEach(applyNow)
    end
    if ns.TargetCells and ns.TargetCells.ApplyBindings then
        ns.TargetCells:ApplyBindings()
    end
end

ns:On("PLAYER_REGEN_ENABLED", function()
    for button in pairs(pendingButtons) do
        applyNow(button)
        pendingButtons[button] = nil
    end
end)

-- Spellbook readiness: at PLAYER_LOGIN, GetSpellInfo can return nil for
-- spells the player actually knows because spell data hasn't streamed
-- in yet. The first ApplyTo (run from Cell:Skin) then silently drops
-- those bindings, and Cell:Skin's `skinned` cache prevents a retry. By
-- the time SPELLS_CHANGED fires, spell data is ready, so re-run ApplyAll
-- to backfill any bindings that got skipped during the cold-load window.
-- /reload masks this because spell data is already cached on the second
-- pass. Also fires when the player learns/unlearns a spell, which is
-- harmless (re-applies identical bindings).
ns:On("SPELLS_CHANGED", function()
    CC:ApplyAll()
end)

-- Per-target buff ranks are baked from each cell's current unit and that
-- unit's level, so they go stale when either changes:
--   GROUP_ROSTER_UPDATE — the secure header re-points a button at a
--      different member; its baked rank was computed for the old unit.
--   UNIT_LEVEL — a member dinged or their level just streamed in, so a
--      higher rank may now be appropriate.
-- Re-bake everything on either. Deferred one frame so the secure
-- header's unit reassignment has settled before we read it; ApplyAll
-- itself no-ops into the pending queue if we're in combat. The flag
-- coalesces a burst (a whole raid's levels streaming in at once) into a
-- single re-bake instead of one per event.
local rebakeQueued = false
local function rebakeSoon()
    if rebakeQueued then return end
    rebakeQueued = true
    C_Timer.After(0, function()
        rebakeQueued = false
        CC:ApplyAll()
    end)
end
ns:On("GROUP_ROSTER_UPDATE", rebakeSoon)
ns:On("UNIT_LEVEL", rebakeSoon)
