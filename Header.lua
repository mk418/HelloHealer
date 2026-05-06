local ADDON_NAME, ns = ...

ns.Header = {}
local Header = ns.Header

-- Horizontal shift applied to the main group header when tanks are
-- present. Tanks live in a single column (TankHeader sets
-- maxColumns=1), so the offset is always one cell width + 4 px gap
-- when any tank exists, and zero when none do. The saved position
-- always represents the no-tank case; this offset is added at draw
-- time and stripped when saving from drag.
local COL_GAP = 4
local function tankOffsetPx(count)
    count = count or 0
    if count == 0 then return 0 end
    return ns.Cell.WIDTH + COL_GAP
end

-- Per-column SecureGroupHeader filters. Four headers, each holding its
-- own single column of up to 10 cells (2 raid groups stacked).
--
-- Why four headers instead of one with maxColumns=4: Blizzard's
-- SecureGroupHeader places new columns by anchoring the new column's
-- columnAnchorPoint to the previous column's *first* button at its
-- opposite point — for columnAnchorPoint="TOPLEFT", that's "BOTTOMRIGHT",
-- which steps each subsequent column 40 px down (one cell height) plus
-- columnSpacing. The result is a staircase, not a grid. There is no
-- columnAnchorPoint value that produces clean horizontal flow without
-- conflicting with point="TOP" on the first button. Splitting into one
-- header per column sidesteps the entire columnAnchorPoint mechanism.
-- See SecureGroupHeaders.lua getRelativePointAnchor + the columnUnitCount==1
-- branch of configureChildren.
local COLUMN_FILTERS = { "1,2", "3,4", "5,6", "7,8" }

-- Track when WE entered a group during combat (solo -> grouped while
-- in combat lockdown). When that's the case, our cells are likely
-- partial / mid-spawn, so we hide both headers (alpha 0) until combat
-- ends and let Blizzard / DragonflightUI frames be the fallback.
-- Detection is specifically a wasInGroup -> nowInGroup transition so
-- the inviter (who didn't change state) keeps their working cells.
-- Registered at file-load time so they run BEFORE skinAll (which is
-- registered at PLAYER_LOGIN inside Header:Create) — order matters,
-- skinAll reads the flag.
local joinedInCombat = false
local wasInGroup = false
ns:On("GROUP_ROSTER_UPDATE", function()
    local nowInGroup = IsInGroup()
    if InCombatLockdown() and not wasInGroup and nowInGroup then
        joinedInCombat = true
    end
    wasInGroup = nowInGroup
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    joinedInCombat = false
end)

local function makeColumn(index, filter, anchorTo, savedPos)
    local h = CreateFrame("Frame", "HelloHealerMainHeader" .. index, UIParent, "SecureGroupHeaderTemplate")
    h:SetMovable(index == 1)

    -- Position first, before attributes — matches the order Blizzard's
    -- SecureGroupHeader expects (its OnAttributeChanged path can re-run
    -- the layout, and a header with no anchor point places children at
    -- (0,0) before being shifted, which DragonflightUI's BuffFrame hook
    -- has misbehaved on in the past).
    if anchorTo then
        h:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", COL_GAP, 0)
    elseif savedPos then
        h:SetPoint(savedPos.point, UIParent, savedPos.point, savedPos.x, savedPos.y)
    end

    -- Only column 1 shows party / solo content; columns 2-4 are
    -- raid-only with their group filter. This means in a 5-man party,
    -- only column 1 has cells (no duplication into empty columns), and
    -- in raid the player only appears in the column whose groupFilter
    -- matches their raid group.
    h:SetAttribute("showSolo",   index == 1)
    h:SetAttribute("showPlayer", index == 1)
    h:SetAttribute("showParty",  index == 1)
    h:SetAttribute("showRaid",   true)

    h:SetAttribute("groupFilter",        filter)
    h:SetAttribute("unitsPerColumn",     10)
    h:SetAttribute("maxColumns",         1)

    h:SetAttribute("point",   "TOP")
    h:SetAttribute("yOffset", -2)

    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("initialConfigFunction", ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(ns.Cell.WIDTH, ns.Cell.HEIGHT))

    return h
end

function Header:Create()
    local pos = HelloHealerCharDB.position

    self.columns = {}
    for i, filter in ipairs(COLUMN_FILTERS) do
        self.columns[i] = makeColumn(i, filter, self.columns[i - 1], pos)
    end

    -- Column 1 holds the saved position; columns 2-4 follow it via
    -- their TOPLEFT-to-TOPRIGHT chain. self.frame remains an alias for
    -- column 1 so existing call sites (TankHeader anchor, TargetCells,
    -- mover, ApplyTankOffset) keep working without churn.
    self.frame = self.columns[1]

    -- Trigger each header's internal update via Hide+Show toggle rather
    -- than calling SecureGroupHeader_Update directly, which DragonflightUI
    -- hooks and accumulates mask textures from on every call.
    for i = 1, #self.columns do
        self.columns[i]:Hide()
        self.columns[i]:Show()
    end

    local function skinAll()
        if not self.columns then return end
        local alpha = joinedInCombat and 0 or 1
        for i = 1, #self.columns do
            local h = self.columns[i]
            -- Force the secure header to re-iterate the group when out of
            -- combat. Necessary on initial login: the Hide+Show in Create()
            -- may run before the client has populated party data, so the
            -- header ends up with only the player. Subsequent
            -- GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD events use this
            -- toggle to make the header re-evaluate.
            if not InCombatLockdown() then
                h:Hide()
                h:Show()
            end
            local kids = { h:GetChildren() }
            for j = 1, #kids do
                local k = kids[j]
                if k:GetAttribute("unit") then
                    ns.Cell:Skin(k)
                end
            end
            -- If a roster change fired during this combat session, our
            -- cells may be partial / mid-spawn — hide them and let the
            -- Blizzard/DragonflightUI frames be the fallback. Restored on
            -- PLAYER_REGEN_ENABLED, when joinedInCombat is cleared.
            h:SetAlpha(alpha)
        end
        if ns.TankHeader and ns.TankHeader.frame then
            ns.TankHeader.frame:SetAlpha(alpha)
        end
    end

    ns:On("GROUP_ROSTER_UPDATE",   skinAll)
    ns:On("PLAYER_ENTERING_WORLD", skinAll)
    -- Post-combat catch-up: when someone joins the group while we're in
    -- combat lockdown, the secure header defers spawning their unit
    -- button until PLAYER_REGEN_ENABLED. Our skinAll doesn't re-run on
    -- that internal catch-up, so the new cell stays unskinned. Re-running
    -- skinAll on combat end picks them up.
    ns:On("PLAYER_REGEN_ENABLED",  skinAll)
    skinAll()

    self:CreateMover()
end

-- Iterate every column header. Used by modules that need to walk all
-- spawned group cells (e.g., Cell:FindByUnit).
function Header:ForEachColumn(fn)
    if not self.columns then return end
    for i = 1, #self.columns do
        fn(self.columns[i], i)
    end
end

-- Apply HelloHealerDB.layout.scale to all of our top-level frames so the
-- group, tank, and target cells scale uniformly. SetScale on a protected
-- frame is combat-blocked, so we no-op in lockdown — the slider in the
-- settings panel is itself out-of-combat-only as a result.
function Header:ApplyScale()
    if InCombatLockdown() then return end
    local s = (HelloHealerDB and HelloHealerDB.layout and HelloHealerDB.layout.scale) or 1.0
    if self.columns then
        for i = 1, #self.columns do
            self.columns[i]:SetScale(s)
        end
    end
    if ns.TankHeader and ns.TankHeader.frame then ns.TankHeader.frame:SetScale(s) end
    if ns.TargetCells then
        if ns.TargetCells.target then ns.TargetCells.target:SetScale(s) end
        if ns.TargetCells.tot    then ns.TargetCells.tot:SetScale(s) end
    end
end

function Header:CreateMover()
    local mover = CreateFrame("Frame", "HelloHealerMover", self.frame)
    mover:SetSize(160, 18)
    mover:SetPoint("BOTTOM", self.frame, "TOP", 0, 4)
    mover:SetFrameStrata("HIGH")

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.5, 0.9, 0.6)
    mover.bg = bg

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("HelloHealer — drag to move")

    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")

    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        self.frame:StartMoving()
    end)
    mover:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        local point, _, _, x, y = self.frame:GetPoint()
        x = x - tankOffsetPx(self.tankOffsetCount or 0)
        HelloHealerCharDB.position.point = point
        HelloHealerCharDB.position.x = x
        HelloHealerCharDB.position.y = y
    end)

    self.mover = mover
    self:RefreshMover()
end

-- Apply the tank-column offset. Takes the current tank count so the
-- shift can grow when the tank block needs a second column. Combat-safe:
-- SetPoint on a SecureGroupHeader is blocked while in lockdown, so we
-- record the new count and defer the actual reposition until
-- PLAYER_REGEN_ENABLED.
function Header:ApplyTankOffset(count)
    count = count or 0
    if self.tankOffsetCount == count then return end
    self.tankOffsetCount = count
    if InCombatLockdown() then
        self.tankOffsetPending = true
        return
    end
    self:Reposition()
end

function Header:Reposition()
    if not self.frame then return end
    local pos = HelloHealerCharDB.position
    local x = pos.x + tankOffsetPx(self.tankOffsetCount or 0)
    self.frame:ClearAllPoints()
    self.frame:SetPoint(pos.point, UIParent, pos.point, x, pos.y)
end

ns:On("PLAYER_REGEN_ENABLED", function()
    if Header.tankOffsetPending then
        Header.tankOffsetPending = false
        Header:Reposition()
    end
end)

function Header:RefreshMover()
    if not self.mover then return end
    if HelloHealerCharDB.locked then
        self.mover:Hide()
    else
        self.mover:Show()
    end
end
