local ADDON_NAME, ns = ...

ns.Bindings = {}
local Bindings = ns.Bindings

-- btn: 1=Left, 2=Right, 3=Middle, 4=Mouse4, 5=Mouse5
-- mod: "" | "shift" | "ctrl" | "alt" or combined in canonical
--      alt-ctrl-shift order, e.g. "ctrl-shift", "alt-ctrl-shift".
Bindings.defaults = {
    PRIEST = {
        { btn = 1, mod = "",           spell = "Flash Heal(Rank 3)" },
        { btn = 1, mod = "shift",      spell = "Flash Heal" },
        { btn = 1, mod = "ctrl",       spell = "Dispel Magic" },
        { btn = 1, mod = "ctrl-shift", spell = "Power Word: Fortitude" },
        { btn = 1, mod = "alt",        spell = "Heal(Rank 3)" },
        { btn = 1, mod = "alt-shift",  spell = "Divine Spirit" },
        { btn = 2, mod = "",           spell = "Renew" },
        { btn = 2, mod = "shift",      spell = "Power Word: Shield" },
        { btn = 2, mod = "ctrl",       spell = "Cure Disease" },
        { btn = 2, mod = "alt-ctrl",   spell = "Resurrection" },
        { btn = 2, mod = "ctrl-shift", spell = "Fear Ward" },
        { btn = 2, mod = "alt",        spell = "Renew(Rank 6)" },
        { btn = 3, mod = "",           spell = "Greater Heal(Rank 2)" },
        { btn = 3, mod = "shift",      spell = "Greater Heal" },
        { btn = 3, mod = "ctrl",       spell = "Abolish Disease" },
        { btn = 3, mod = "ctrl-shift", spell = "Prayer of Fortitude" },
        { btn = 3, mod = "alt",        spell = "Greater Heal(Rank 1)" },
        { btn = 3, mod = "alt-shift",  spell = "Prayer of Spirit" },
    },
    DRUID = {
        { btn = 1, mod = "",           spell = "Healing Touch(Rank 4)" },
        { btn = 1, mod = "shift",      spell = "Healing Touch" },
        { btn = 1, mod = "ctrl",       spell = "Remove Curse" },
        { btn = 1, mod = "ctrl-shift", spell = "Mark of the Wild" },
        { btn = 1, mod = "alt",        spell = "Nature's Swiftness" },
        { btn = 2, mod = "",           spell = "Rejuvenation" },
        { btn = 2, mod = "shift",      spell = "Rejuvenation" },
        { btn = 2, mod = "ctrl",       spell = "Abolish Poison" },
        { btn = 2, mod = "alt-ctrl",   spell = "Rebirth" },
        { btn = 2, mod = "ctrl-shift", spell = "Thorns" },
        { btn = 3, mod = "",           spell = "Regrowth(Rank 4)" },
        { btn = 3, mod = "shift",      spell = "Regrowth" },
        { btn = 3, mod = "ctrl",       spell = "Cure Poison" },
        { btn = 3, mod = "alt-ctrl",   spell = "Innervate" },
        { btn = 3, mod = "ctrl-shift", spell = "Gift of the Wild" },
    },
    SHAMAN = {
        { btn = 1, mod = "",           spell = "Healing Wave(Rank 5)" },
        { btn = 1, mod = "shift",      spell = "Healing Wave" },
        { btn = 1, mod = "ctrl",       spell = "Cure Disease" },
        { btn = 1, mod = "alt",        spell = "Healing Wave(Rank 1)" },
        { btn = 2, mod = "",           spell = "Chain Heal(Rank 3)" },
        { btn = 2, mod = "shift",      spell = "Chain Heal" },
        { btn = 2, mod = "ctrl",       spell = "Cure Poison" },
        { btn = 2, mod = "alt",        spell = "Chain Heal(Rank 1)" },
        { btn = 2, mod = "alt-ctrl",   spell = "Ancestral Spirit" },
        { btn = 3, mod = "",           spell = "Lesser Healing Wave(Rank 4)" },
        { btn = 3, mod = "shift",      spell = "Lesser Healing Wave" },
    },
    PALADIN = {
        { btn = 1, mod = "",           spell = "Flash of Light(Rank 4)" },
        { btn = 1, mod = "shift",      spell = "Flash of Light" },
        { btn = 1, mod = "ctrl",       spell = "Cleanse" },
        { btn = 1, mod = "ctrl-shift", spell = "Blessing of Protection" },
        { btn = 2, mod = "",           spell = "Holy Light" },
        { btn = 2, mod = "shift",      spell = "Holy Light" },
        { btn = 2, mod = "ctrl",       spell = "Purify" },
        { btn = 2, mod = "alt-ctrl",   spell = "Redemption" },
        { btn = 2, mod = "ctrl-shift", spell = "Blessing of Freedom" },
        { btn = 3, mod = "",           spell = "Lay on Hands" },
        { btn = 3, mod = "shift",      spell = "Lay on Hands" },
        { btn = 3, mod = "ctrl-shift", spell = "Blessing of Salvation" },
    },
}

-- Return the effective binding list for the player's class: defaults
-- with HelloHealerCharDB.bindings entries layered on top. Each
-- override matches a (btn, mod) pair: setting spell to "" (or nil)
-- removes that slot, otherwise it adds/replaces.
function Bindings:Get()
    local class = ns.playerClass
    local result = {}
    for _, b in ipairs(self.defaults[class] or {}) do
        table.insert(result, { btn = b.btn, mod = b.mod, spell = b.spell })
    end
    for _, b in ipairs(HelloHealerCharDB and HelloHealerCharDB.bindings or {}) do
        local matched
        for i, r in ipairs(result) do
            if r.btn == b.btn and r.mod == b.mod then
                matched = i
                break
            end
        end
        if b.spell and b.spell ~= "" then
            if matched then
                result[matched].spell = b.spell
            else
                table.insert(result, { btn = b.btn, mod = b.mod, spell = b.spell })
            end
        else
            -- Empty spell == remove
            if matched then table.remove(result, matched) end
        end
    end
    return result
end

-- Resolve a stored spell name to one the player actually knows.
-- Returns (name, exact, rank):
--   name:  fully-qualified spell to bind/display, including rank
--          suffix when ranks apply ("Lesser Healing Wave(Rank 6)").
--   exact: true if the stored name resolves as-is (the user got what
--          they stored), false if we substituted another rank to keep
--          the click working on a leveling character.
--   rank:  numeric rank that will actually be cast, or nil for
--          single-rank spells (Nature's Swiftness, Resurrection).
-- Returns nil for `name` when the player knows no rank of the spell.
--
-- Why: defaults bake in level-60 ranks (e.g. "Lesser Healing Wave(Rank
-- 4)"). On a leveling character the exact rank doesn't exist yet, so
-- we probe down from a safe cap (12 covers all Era healing spells) and
-- bind the highest known rank instead — gives the leveling player a
-- working click without forcing them to rebind, while preserving the
-- curated downrank choices for a level-60 player whose exact rank
-- resolves on the first try. Unranked stored bindings ("Healing Wave"
-- with no suffix) are also probed so the tooltip can show "Rank 6" —
-- the cast itself is unchanged either way (Blizzard auto-resolves
-- unranked casts to the highest known rank).
function Bindings:Resolve(spellName)
    if not spellName or spellName == "" then return nil, false, nil end

    local base, askedRank = spellName:match("^(.-)%(Rank (%d+)%)$")

    if base then
        askedRank = tonumber(askedRank)
        if GetSpellInfo(spellName) then return spellName, true, askedRank end
        for r = 12, 1, -1 do
            if r ~= askedRank then
                local candidate = base .. "(Rank " .. r .. ")"
                if GetSpellInfo(candidate) then return candidate, false, r end
            end
        end
        if GetSpellInfo(base) then return base, false, nil end
        return nil, false, nil
    end

    if not GetSpellInfo(spellName) then return nil, false, nil end
    for r = 12, 1, -1 do
        local candidate = spellName .. "(Rank " .. r .. ")"
        if GetSpellInfo(candidate) then return candidate, true, r end
    end
    return spellName, true, nil
end

-- Scaling group buffs whose rank carries a minimum *target* level: the
-- game refuses "Target is too low level" when a rank is cast on someone
-- below the level that rank was introduced at. Each entry is, per rank
-- (index = rank number), that introduction level — i.e. the level a
-- character trains the rank at.
--
-- We use the train level as the minimum-target gate. The real engine
-- floor (DBC BaseLevel) is always <= the train level, so gating on the
-- train level can never produce a cast the engine then rejects as "too
-- low" — it only, at the very top end, picks one rank lower than
-- strictly necessary for a target within a few levels of max. That
-- trade (guaranteed-castable, occasionally one rank shy near 60) is the
-- right one: the whole point is that the buff *lands*. Values verified
-- against the Classic Era spell database.
local BUFF_TARGET_LEVELS = {
    ["Power Word: Fortitude"] = { 1, 12, 24, 36, 48, 60 },
    ["Prayer of Fortitude"]   = { 48, 60 },
    ["Divine Spirit"]         = { 30, 40, 50, 60 },
    ["Prayer of Spirit"]      = { 60 },
    ["Mark of the Wild"]      = { 1, 10, 20, 30, 40, 50, 60 },
    ["Gift of the Wild"]      = { 50, 60 },
    ["Thorns"]                = { 6, 14, 24, 34, 44, 54 },
}

-- Like Resolve, but additionally downranks scaling buffs to the highest
-- rank the *target* is high enough to receive, so casting Fortitude on a
-- low-level character lands a working rank instead of erroring "Target
-- is too low level". Returns (name, exact, rank) with the same meaning
-- as Resolve, except `exact` is also false when we dropped below the
-- rank Resolve would have cast purely because of the target's level
-- (surfaces the downrank in the tooltip).
--
-- targetLevel may be nil/unknown (alias cells, units not yet streamed
-- in); in that case, and for any spell without a level table (heals,
-- single-rank utility, buffs we don't track), this is exactly Resolve —
-- so it is always safe to call in place of Resolve.
function Bindings:ResolveForTarget(spellName, targetLevel)
    local rName, rExact, rRank = self:Resolve(spellName)
    if not rName then return rName, rExact, rRank end

    local base = spellName:match("^(.-)%(Rank %d+%)$") or spellName
    local levels = BUFF_TARGET_LEVELS[base]
    if not levels or not targetLevel or targetLevel <= 0 then
        return rName, rExact, rRank
    end

    -- rRank already reflects both the caster's highest known rank and any
    -- explicit rank the user stored, so it is the correct upper bound —
    -- never cast higher than the player asked for or can cast.
    local cap = rRank or #levels
    if cap > #levels then cap = #levels end
    for r = cap, 1, -1 do
        if targetLevel >= levels[r] then
            local candidate = base .. "(Rank " .. r .. ")"
            if GetSpellInfo(candidate) then
                return candidate, (r == rRank) and rExact or false, r
            end
        end
    end

    -- Target is below even the lowest rank's floor (e.g. Prayer of
    -- Fortitude, which starts at Rank 1 / level 48, on a level-30
    -- target). No rank can land — keep Resolve's choice so behaviour
    -- matches today rather than silently dropping the click.
    return rName, rExact, rRank
end

function Bindings:Set(btn, mod, spell)
    HelloHealerCharDB.bindings = HelloHealerCharDB.bindings or {}
    for _, b in ipairs(HelloHealerCharDB.bindings) do
        if b.btn == btn and b.mod == mod then
            b.spell = spell
            return
        end
    end
    table.insert(HelloHealerCharDB.bindings, { btn = btn, mod = mod, spell = spell })
end

-- WoW's Interface → Options → Combat → "Self Cast Key" exposes a
-- modifier that forces any spell cast while held onto the player —
-- and in Classic Era this override beats explicit [@mouseover] in
-- click-cast macros. Returns the modifier as a lowercase token
-- ("alt"/"ctrl"/"shift") matching our stored binding format, or nil
-- when Self Cast Key is unbound.
function Bindings:SelfCastModifier()
    if not GetModifiedClick then return nil end
    local key = GetModifiedClick("SELFCAST")
    if not key or key == "" or key == "NONE" then return nil end
    return key:lower()
end

-- True when this binding's modifier string contains the self-cast
-- token, meaning the click will self-cast instead of landing on the
-- moused-over frame.
function Bindings:ConflictsWithSelfCast(mod)
    local sc = self:SelfCastModifier()
    if not sc or not mod then return false end
    for tok in mod:gmatch("[^%-]+") do
        if tok == sc then return true end
    end
    return false
end

-- Clear WoW's Self Cast Key and persist to the active binding set so
-- the change survives /reload. Returns:
--   true       — cleared
--   false      — already unbound, no-op
--   nil, "combat" — SaveBindings is combat-locked; caller should retry
--                   after PLAYER_REGEN_ENABLED.
function Bindings:DisableSelfCast()
    if not self:SelfCastModifier() then return false end
    if InCombatLockdown() then return nil, "combat" end
    if SetModifiedClick then SetModifiedClick("SELFCAST", "NONE") end
    if SaveBindings then
        local set = (GetCurrentBindingSet and GetCurrentBindingSet()) or 1
        SaveBindings(set)
    end
    return true
end

-- Removing a non-default binding deletes the override entirely; for
-- a default entry we store an empty-string override to suppress it.
function Bindings:Unset(btn, mod)
    HelloHealerCharDB.bindings = HelloHealerCharDB.bindings or {}
    local class = ns.playerClass
    local isDefault = false
    for _, d in ipairs(self.defaults[class] or {}) do
        if d.btn == btn and d.mod == mod then isDefault = true break end
    end
    for i, b in ipairs(HelloHealerCharDB.bindings) do
        if b.btn == btn and b.mod == mod then
            if isDefault then
                b.spell = ""
            else
                table.remove(HelloHealerCharDB.bindings, i)
            end
            return
        end
    end
    if isDefault then
        table.insert(HelloHealerCharDB.bindings, { btn = btn, mod = mod, spell = "" })
    end
end
