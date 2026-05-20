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
        { btn = 1, mod = "",           spell = "Lesser Healing Wave(Rank 4)" },
        { btn = 1, mod = "shift",      spell = "Lesser Healing Wave" },
        { btn = 1, mod = "ctrl",       spell = "Cure Disease" },
        { btn = 1, mod = "alt",        spell = "Nature's Swiftness" },
        { btn = 2, mod = "",           spell = "Chain Heal(Rank 1)" },
        { btn = 2, mod = "shift",      spell = "Chain Heal" },
        { btn = 2, mod = "ctrl",       spell = "Cure Poison" },
        { btn = 2, mod = "alt-ctrl",   spell = "Ancestral Spirit" },
        { btn = 3, mod = "",           spell = "Healing Wave(Rank 6)" },
        { btn = 3, mod = "shift",      spell = "Healing Wave" },
        { btn = 3, mod = "alt",        spell = "Healing Wave(Rank 4)" },
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
