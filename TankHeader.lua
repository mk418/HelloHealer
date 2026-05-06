local ADDON_NAME, ns = ...

ns.TankHeader = {}
local TankHeader = ns.TankHeader

-- The secure header is driven by `nameList` exclusively: when nameList
-- is set, the header iterates that list and ignores groupFilter. We
-- build the list from two sources merged together:
--   1. HelloHealerCharDB.tankList — user-added names (`/hh tank <name>`)
--   2. Raid /maintank and /mainassist-marked players, looked up live
-- This means the tank column shows manual entries AND raid-leader-marked
-- tanks, with the same code path.
local function isTankUnit(unit)
    if UnitGroupRolesAssigned then
        if UnitGroupRolesAssigned(unit) == "TANK" then return true end
    end
    if GetPartyAssignment then
        if GetPartyAssignment("MAINTANK", unit) or GetPartyAssignment("MAINASSIST", unit) then
            return true
        end
    end
    return false
end

-- Return "Name-Realm" for cross-realm units, plain "Name" otherwise.
-- Cross-realm groups (connected realms in Classic Era) can include two
-- players with the same name from different realms; SecureGroupHeader's
-- nameList disambiguates only when entries include the realm suffix.
local function fullName(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

ns.TankHeader.FullName = fullName

-- Resolve a typed name to its full "Name-Realm" form by searching the
-- current group. Returns the disambiguated form when there's exactly
-- one match, otherwise returns the typed name as-is so the player can
-- join the group later (or the user can specify the realm explicitly
-- when there's a cross-realm conflict).
function ns.TankHeader:ResolveName(typed)
    if not typed or typed == "" then return typed end
    -- If the user already typed "Name-Realm", trust it.
    if typed:find("-", 1, true) then return typed end

    local typedLower = typed:lower()
    local matches = {}

    local function check(unit)
        if not UnitExists(unit) then return end
        local n = UnitName(unit)
        if n and n:lower() == typedLower then
            local full = fullName(unit)
            for _, m in ipairs(matches) do if m == full then return end end
            table.insert(matches, full)
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do check("raid" .. i) end
    elseif IsInGroup() then
        check("player")
        for i = 1, 4 do check("party" .. i) end
    else
        check("player")
    end

    if #matches == 1 then return matches[1] end
    if #matches > 1 then
        print(("|cff80ff80HelloHealer|r multiple players named %s — include realm to disambiguate (e.g., %s)"):format(typed, matches[1]))
    end
    return typed
end

local function buildNameList()
    local names = {}
    local seen = {}

    local function add(name)
        if not name then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        table.insert(names, name)
    end

    for _, name in ipairs(HelloHealerCharDB.tankList or {}) do
        add(name)
    end

    local function check(unit)
        if UnitExists(unit) and isTankUnit(unit) then
            add(fullName(unit))
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do check("raid" .. i) end
    elseif IsInGroup() then
        check("player")
        for i = 1, 4 do check("party" .. i) end
    else
        check("player")
    end

    return table.concat(names, ",")
end

function TankHeader:Create()
    if not ns.Header.frame then return end

    local h = CreateFrame("Frame", "HelloHealerTankHeader", ns.Header.frame, "SecureGroupHeaderTemplate")
    h:SetPoint("TOPRIGHT", ns.Header.frame, "TOPLEFT", -4, 0)

    h:SetAttribute("showSolo",   false)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("showParty",  true)
    h:SetAttribute("showRaid",   true)

    h:SetAttribute("nameList",           buildNameList())
    -- Single tall column — matches the main header's 10-per-column
    -- packing so the tank column's height lines up with the group
    -- block's first column. Caps at 10 tanks; beyond that they fall
    -- off, which is acceptable since real-world raids run ≤10 tanks.
    h:SetAttribute("unitsPerColumn",     10)
    h:SetAttribute("maxColumns",         1)
    h:SetAttribute("columnSpacing",      4)
    h:SetAttribute("columnAnchorPoint",  "TOPRIGHT")

    h:SetAttribute("point",   "TOP")
    h:SetAttribute("yOffset", -2)

    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("initialConfigFunction", ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(ns.Cell.WIDTH, ns.Cell.HEIGHT))

    self.frame = h

    h:Hide()
    h:Show()

    local function skinAll()
        if not self.frame then return end
        local count = 0
        local kids = { self.frame:GetChildren() }
        for i = 1, #kids do
            local k = kids[i]
            if k:GetAttribute("unit") then
                ns.Cell:Skin(k)
                count = count + 1
            end
        end
        -- Pass the actual count so Header can size the offset to the
        -- tank-block width (1 column ≤5 tanks, 2 columns 6–10 tanks).
        ns.Header:ApplyTankOffset(count)
    end

    self.skinAll = skinAll

    -- Re-derive the nameList on every roster/leader change so /maintank
    -- markings are picked up live (these don't fire as a separate event;
    -- the secure header relies on the same broadcasts).
    local function refreshAll()
        TankHeader:RefreshNameList()
    end

    ns:On("GROUP_ROSTER_UPDATE",   refreshAll)
    ns:On("PLAYER_ENTERING_WORLD", refreshAll)
    ns:On("PARTY_LEADER_CHANGED",  refreshAll)
    ns:On("PLAYER_ROLES_ASSIGNED", refreshAll)
    ns:On("RAID_ROSTER_UPDATE",    refreshAll)
    ns:On("PLAYER_REGEN_ENABLED", function()
        if self.pendingNameListRefresh then
            self.pendingNameListRefresh = false
            self:RefreshNameList()
        else
            skinAll()
        end
    end)
    skinAll()
end

-- Recompute and push the merged nameList into the secure header.
-- SetAttribute on a SecureGroupHeader is blocked in combat, so we defer
-- to PLAYER_REGEN_ENABLED.
function TankHeader:RefreshNameList()
    if not self.frame then return end
    if InCombatLockdown() then
        self.pendingNameListRefresh = true
        return
    end
    self.frame:SetAttribute("nameList", buildNameList())
    self.frame:Hide()
    self.frame:Show()
    if self.skinAll then self.skinAll() end
end
