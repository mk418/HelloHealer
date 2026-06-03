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

    -- groupBy + groupingOrder force the secure header to place units
    -- in subgroup-then-raid-index order instead of pure raid-index
    -- order. Without this, a column with filter "3,4" interleaves
    -- group 3 and group 4 players based on the order they joined the
    -- raid; with this, group 3 fills the top half and group 4 the
    -- bottom. It also makes the secure header re-evaluate slot
    -- placement on subgroup-only changes — without groupBy, a player
    -- moving from group 3 to group 5 can keep their cell slot until
    -- the next stronger refresh, leaving the tooltip's "Group N" line
    -- contradicting the column the cell sits in. groupingOrder mirrors
    -- the column's groupFilter so the order matches what's filtered in.
    h:SetAttribute("groupBy",        "GROUP")
    h:SetAttribute("groupingOrder",  filter)

    h:SetAttribute("point",   "TOP")
    h:SetAttribute("yOffset", -2)

    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("initialConfigFunction", ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(ns.Cell.WIDTH, ns.Cell.HEIGHT))

    return h
end

-- Right-most player column that currently has a spawned unit cell.
-- In a 5-man party only col 1 is populated; in raid it depends on
-- which groups exist. The pet column anchors to this so it sits
-- flush with the player block, instead of leaving gaps for empty
-- raid-only columns. Falls back to col 1 if nothing is populated.
local function lastPopulatedColumn(columns)
    if not columns then return nil end
    for i = #columns, 1, -1 do
        local kids = { columns[i]:GetChildren() }
        for j = 1, #kids do
            local unit = kids[j]:GetAttribute("unit")
            if unit and UnitExists(unit) then
                return columns[i]
            end
        end
    end
    return columns[1]
end

-- Pet column. Lives to the right of the last populated player column
-- (see Header:ReanchorPetColumn) and uses SecureGroupPetHeaderTemplate,
-- which iterates pet unit tokens (raidpetN / partypetN / pet) instead
-- of player tokens. Existence is unconditional; visibility is driven by
-- HelloHealerCharDB.showPets via Header:ApplyShowPets so toggling on/off
-- doesn't require recreating the secure frame (which would be
-- combat-blocked).
local function makePetColumn()
    local h = CreateFrame("Frame", "HelloHealerPetHeader", UIParent, "SecureGroupPetHeaderTemplate")

    h:SetAttribute("showSolo",   true)
    h:SetAttribute("showPlayer", true)
    h:SetAttribute("showParty",  true)
    h:SetAttribute("showRaid",   true)

    -- Single tall column. Hunters/warlocks/DKs are the only common
    -- pet-bearing classes, so 40 is a safe ceiling that avoids the
    -- multi-column staircase issue documented above for the player
    -- columns.
    h:SetAttribute("unitsPerColumn", 40)
    h:SetAttribute("maxColumns",     1)

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

    self.petColumn = makePetColumn()

    -- Trigger each header's internal update via Hide+Show toggle rather
    -- than calling SecureGroupHeader_Update directly, which DragonflightUI
    -- hooks and accumulates mask textures from on every call.
    for i = 1, #self.columns do
        self.columns[i]:Hide()
        self.columns[i]:Show()
    end

    local function skinAll()
        if not self.columns then return end
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
        end
        if self.petColumn and HelloHealerCharDB and HelloHealerCharDB.showPets then
            self:ReanchorPetColumn()
            if not InCombatLockdown() then
                self.petColumn:Hide()
                self.petColumn:Show()
            end
            local kids = { self.petColumn:GetChildren() }
            for j = 1, #kids do
                local k = kids[j]
                if k:GetAttribute("unit") then
                    ns.Cell:Skin(k)
                end
            end
        end
    end

    self.skinAll = skinAll

    ns:On("GROUP_ROSTER_UPDATE",   skinAll)
    ns:On("PLAYER_ENTERING_WORLD", skinAll)
    -- RAID_ROSTER_UPDATE is officially deprecated in favour of
    -- GROUP_ROSTER_UPDATE, but it still fires in Classic Era and
    -- catches some subgroup-only edits that GROUP_ROSTER_UPDATE
    -- occasionally misses. Belt-and-suspenders so a subgroup move
    -- doesn't leave a cell stuck on the previous unit until the next
    -- stronger refresh trigger.
    ns:On("RAID_ROSTER_UPDATE",    skinAll)
    -- Pet summon / dismiss / change: SecureGroupPetHeaderTemplate spawns
    -- the new pet's cell internally, but our skin pass needs to run
    -- against any newly-created child button.
    ns:On("UNIT_PET",              skinAll)
    -- Post-combat catch-up: when someone joins the group while we're in
    -- combat lockdown, the secure header defers spawning their unit
    -- button until PLAYER_REGEN_ENABLED. Our skinAll doesn't re-run on
    -- that internal catch-up, so the new cell stays unskinned. Re-running
    -- skinAll on combat end picks them up.
    ns:On("PLAYER_REGEN_ENABLED",  skinAll)
    skinAll()

    self:ApplyShowPets()
    self:CreateMover()
    self:ApplyVisibility()
end

-- Show or hide every frame this addon owns based on
-- HelloHealerCharDB.framesHidden. Used by the /hh frames slash
-- command and re-applied at login so the saved state persists.
-- Hide()/Show() on a SecureGroupHeader is combat-blocked, so changes
-- made in lockdown defer to PLAYER_REGEN_ENABLED. Mover is parented
-- to column 1, so it auto-hides with its parent — no extra wiring.
-- TankHeader and TargetCells live as siblings, so they need explicit
-- toggles. Pet column re-show is conditional on showPets so we don't
-- expose the pet column to a player who has it disabled.
function Header:ApplyVisibility()
    if InCombatLockdown() then
        self.pendingVisibility = true
        return
    end
    self.pendingVisibility = false

    local hide = HelloHealerCharDB and HelloHealerCharDB.framesHidden

    if self.columns then
        for i = 1, #self.columns do
            if hide then self.columns[i]:Hide() else self.columns[i]:Show() end
        end
    end

    if self.petColumn then
        if hide then
            self.petColumn:Hide()
        elseif HelloHealerCharDB and HelloHealerCharDB.showPets then
            self.petColumn:Show()
        end
    end

    if ns.TankHeader and ns.TankHeader.frame then
        if hide then ns.TankHeader.frame:Hide() else ns.TankHeader.frame:Show() end
    end

    if ns.TargetCells then
        if ns.TargetCells.target then
            if hide then ns.TargetCells.target:Hide() else ns.TargetCells.target:Show() end
        end
        if ns.TargetCells.tot then
            if hide then ns.TargetCells.tot:Hide() else ns.TargetCells.tot:Show() end
        end
    end

    if self.RefreshMover then self:RefreshMover() end

    if ns.Settings and ns.Settings.RefreshFramesCheckbox then
        ns.Settings:RefreshFramesCheckbox()
    end
end

-- Show or hide the pet column based on HelloHealerCharDB.showPets.
-- Hide()/Show() on a SecureGroupHeader is combat-blocked, so changes
-- made in lockdown are deferred to PLAYER_REGEN_ENABLED.
function Header:ApplyShowPets()
    if not self.petColumn then return end
    if InCombatLockdown() then
        self.pendingShowPets = true
        return
    end
    self.pendingShowPets = false
    if HelloHealerCharDB and HelloHealerCharDB.showPets then
        self:ReanchorPetColumn()
        -- Re-iterate so currently-existing pets spawn their cells.
        self.petColumn:Hide()
        self.petColumn:Show()
        if self.skinAll then self.skinAll() end
    else
        self.petColumn:Hide()
    end

    if ns.Settings and ns.Settings.RefreshPetsCheckbox then
        ns.Settings:RefreshPetsCheckbox()
    end
end

-- Anchor the pet column to the rightmost player column that has at
-- least one spawned unit. Re-runs on every skinAll so the anchor moves
-- with roster changes (party → raid, group additions). SetPoint on a
-- SecureGroupHeader is combat-blocked, so we defer to PLAYER_REGEN_ENABLED.
function Header:ReanchorPetColumn()
    if not self.petColumn or not self.columns then return end
    if InCombatLockdown() then
        self.pendingPetReanchor = true
        return
    end
    self.pendingPetReanchor = false
    local target = lastPopulatedColumn(self.columns)
    if not target or target == self.petAnchorTo then return end
    self.petAnchorTo = target
    self.petColumn:ClearAllPoints()
    self.petColumn:SetPoint("TOPLEFT", target, "TOPRIGHT", COL_GAP, 0)
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
    if self.petColumn then self.petColumn:SetScale(s) end
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
    if Header.pendingShowPets then
        Header:ApplyShowPets()
    end
    if Header.pendingPetReanchor then
        Header:ReanchorPetColumn()
    end
    if Header.pendingVisibility then
        Header:ApplyVisibility()
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
