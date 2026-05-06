local ADDON_NAME, ns = ...

-- Dev-only visual mock of the addon's frame layout. Spawns
-- non-secure cells in the same geometry the SecureGroupHeader and
-- TankHeader would produce, so we can eyeball overflow / sizing /
-- positioning without needing a real raid roster. Cells are skinned
-- via ns.Cell:Skin against unit="player" — they read live data, but
-- the unit attribute is non-secure here so click-cast is a no-op
-- (clicks do nothing on the mock).

ns.TestLayout = {}
local TL = ns.TestLayout

local COL_GAP = 4
local ROW_GAP = 2
local PAD     = 16
local TITLE_H = 28

local function buildMockCell(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ns.Cell.WIDTH, ns.Cell.HEIGHT)
    b:SetAttribute("unit", "player")
    ns.Cell:Skin(b)
    return b
end

local function ensureFrame()
    if TL.frame then return TL.frame end

    local f = CreateFrame("Frame", "HelloHealerTestLayout", UIParent, "BackdropTemplate")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.55)
    f:SetBackdropBorderColor(0.4, 0.7, 1, 0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -8)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    f.cells = {}
    TL.frame = f
    return f
end

-- Lay out the cells inside the frame, sizing the frame to fit. Reuses
-- existing cells across calls so repeated /hh testlayout invocations
-- with different counts don't leak frames (WoW frames are
-- non-collectable for the session).
local function layout(groupCount, tankCount)
    local f = ensureFrame()
    f.title:SetText(("Layout test: %d-man + %d tanks"):format(groupCount, tankCount))

    -- Geometry mirrors the live secure-header attributes: both tanks
    -- and groups pack 10 per column (TankHeader: unitsPerColumn=10
    -- maxColumns=1, Header: unitsPerColumn=10 maxColumns=4) so the
    -- tank column lines up with the group block's height. Keep these
    -- constants in sync if the live attributes change in Header.lua /
    -- TankHeader.lua.
    local CW, CH = ns.Cell.WIDTH, ns.Cell.HEIGHT
    local TANK_PER_COL  = 10
    local GROUP_PER_COL = 10
    local tankCols  = (tankCount  > 0) and math.ceil(tankCount  / TANK_PER_COL)  or 0
    local groupCols = (groupCount > 0) and math.ceil(groupCount / GROUP_PER_COL) or 0
    local tankRows  = (tankCols  > 0) and math.min(tankCount,  TANK_PER_COL)  or 0
    local groupRows = (groupCols > 0) and math.min(groupCount, GROUP_PER_COL) or 0
    local maxRows   = math.max(tankRows, groupRows)

    local tankBlockW  = (tankCols  > 0) and (tankCols  * CW + (tankCols  - 1) * COL_GAP) or 0
    local groupBlockW = (groupCols > 0) and (groupCols * CW + (groupCols - 1) * COL_GAP) or 0
    local cellsBlockW = tankBlockW + (tankCols > 0 and COL_GAP or 0) + groupBlockW
    local cellsBlockH = maxRows * CH + math.max(0, maxRows - 1) * ROW_GAP

    f:SetSize(PAD * 2 + cellsBlockW, PAD + TITLE_H + cellsBlockH + PAD)
    if not f:GetPoint() then f:SetPoint("CENTER") end

    local needed = groupCount + tankCount
    -- Grow the cell pool if needed; cells are reused from previous calls.
    while #f.cells < needed do
        f.cells[#f.cells + 1] = buildMockCell(f)
    end
    -- Hide any extras from a previous larger call.
    for i = needed + 1, #f.cells do
        f.cells[i]:Hide()
        f.cells[i]:ClearAllPoints()
    end

    local cellsTopY  = -(TITLE_H)
    local cellsLeftX = PAD
    local idx = 0

    -- Tank block: real layout uses columnAnchorPoint=TOPRIGHT, so the
    -- *first* tank column is the rightmost (closest to the group block).
    -- Mirror that here so column overflow direction matches reality.
    for i = 1, tankCount do
        local col = math.floor((i - 1) / TANK_PER_COL)  -- 0 = right column
        local row = (i - 1) % TANK_PER_COL
        idx = idx + 1
        local b = f.cells[idx]
        b:Show()
        b:ClearAllPoints()
        local x = cellsLeftX + (tankCols - 1 - col) * (CW + COL_GAP)
        local y = cellsTopY  - row * (CH + ROW_GAP)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    end

    -- Group block: up to 4 columns × 10 rows, columnAnchorPoint=TOPLEFT.
    -- Two parties stack per column (groups 1+2 in column 1, 3+4 in 2,
    -- etc.) — that's just unitsPerColumn=10 falling out of the
    -- group-ordered iteration; nothing special is needed here.
    local groupX0 = cellsLeftX + tankBlockW + (tankCols > 0 and COL_GAP or 0)
    for i = 1, groupCount do
        local col = math.floor((i - 1) / GROUP_PER_COL)
        local row = (i - 1) % GROUP_PER_COL
        idx = idx + 1
        local b = f.cells[idx]
        b:Show()
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f, "TOPLEFT",
            groupX0 + col * (CW + COL_GAP),
            cellsTopY - row * (CH + ROW_GAP))
    end
end

function TL:Show(groupCount, tankCount)
    groupCount = tonumber(groupCount) or 40
    tankCount  = tonumber(tankCount)  or 8
    layout(groupCount, tankCount)
    TL.frame:Show()
end

function TL:Toggle(groupCount, tankCount)
    if TL.frame and TL.frame:IsShown() then
        TL.frame:Hide()
    else
        TL:Show(groupCount, tankCount)
    end
end
