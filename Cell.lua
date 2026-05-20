local ADDON_NAME, ns = ...

ns.Cell = {}
local Cell = ns.Cell

local CELL_WIDTH  = 80
local CELL_HEIGHT = 40

local skinned = {}

local BUTTON_NAMES = {
    [1] = "Left click",
    [2] = "Right click",
    [3] = "Middle click",
    [4] = "Mouse4",
    [5] = "Mouse5",
}

-- Look up the highest known rank + mana cost of a spell by name.
local function spellRankAndCost(spellName)
    local name, rank, _, _, _, _, spellID = GetSpellInfo(spellName)
    if not name then return nil, nil end

    local manaCost
    local costs
    if C_Spell and C_Spell.GetSpellPowerCost then
        costs = C_Spell.GetSpellPowerCost(spellID)
    elseif GetSpellPowerCost then
        costs = GetSpellPowerCost(spellID)
    end
    if costs then
        for _, c in ipairs(costs) do
            local ptype = c.type or c.powerType
            if ptype == 0 or ptype == (Enum and Enum.PowerType and Enum.PowerType.Mana) then
                manaCost = c.cost or c.minCost
                break
            end
        end
    end

    return rank, manaCost
end

-- Build the canonical modifier string from the keys currently held.
-- Order: alt-ctrl-shift, joined with "-". Matches the SecureUnitButton
-- attribute prefix order, so a binding stored as e.g. "ctrl-shift"
-- maps cleanly to the secure attribute "ctrl-shift-type1".
local function currentModifier()
    local parts = {}
    if IsAltKeyDown()     then table.insert(parts, "alt")   end
    if IsControlKeyDown() then table.insert(parts, "ctrl")  end
    if IsShiftKeyDown()   then table.insert(parts, "shift") end
    return table.concat(parts, "-")
end

local function prettyModifier(mod)
    if mod == "" then return "No modifier" end
    local parts = {}
    for tok in mod:gmatch("[^%-]+") do
        table.insert(parts, (tok:gsub("^%l", string.upper)))
    end
    return table.concat(parts, " + ")
end

-- Custom tooltip frame: GameTooltip auto-fades and is shared with
-- countless other systems, which causes flicker and disappearance. A
-- dedicated frame lets us keep the tooltip pinned to the cell until
-- the user clicks or moves off, and lets us rebuild contents when the
-- modifier state changes without any fade animation.
local tooltip
local hoveredButton

local function ensureTooltip()
    if tooltip then return tooltip end
    local f = CreateFrame("Frame", "HelloHealerTooltip", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:Hide()
    f.lines = {}

    -- Live countdown for time-bearing lines (HoTs, defensive CDs). Each
    -- line that wants a ticking timer stores its expiration on
    -- line.timerExp; we recompute the right-side text every 0.1s while
    -- the tooltip is visible. OnUpdate doesn't fire while hidden, so
    -- there's no cost when you're not hovering a cell.
    f:SetScript("OnUpdate", function(self, elapsed)
        self.tickAccum = (self.tickAccum or 0) + elapsed
        if self.tickAccum < 0.1 then return end
        self.tickAccum = 0
        local now = GetTime()
        for i = 1, #self.lines do
            local line = self.lines[i]
            if line.timerExp and line.right:IsShown() then
                local remain = line.timerExp - now
                if remain > 0 then
                    line.right:SetText(("%.1fs"):format(remain))
                else
                    line.right:SetText("—")
                end
            end
        end
    end)

    tooltip = f
    return f
end

local function tooltipLine(f, idx)
    if f.lines[idx] then return f.lines[idx] end
    local left = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    left:SetJustifyH("LEFT")
    local right = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    right:SetJustifyH("RIGHT")
    local entry = { left = left, right = right }
    f.lines[idx] = entry
    return entry
end

local function layoutTooltip(f, lineCount)
    local PAD_X, PAD_Y, GAP = 10, 8, 4
    local maxLeft, maxRight = 0, 0
    for i = 1, lineCount do
        local line = f.lines[i]
        if line.left:IsShown() then
            local w = line.left:GetStringWidth()
            if w > maxLeft then maxLeft = w end
        end
        if line.right:IsShown() then
            local w = line.right:GetStringWidth()
            if w > maxRight then maxRight = w end
        end
    end
    local rowGap = (maxRight > 0) and 18 or 0
    local contentW = maxLeft + rowGap + maxRight
    local rowH = 14
    local contentH = lineCount * rowH

    f:SetWidth(contentW + PAD_X * 2)
    f:SetHeight(contentH + PAD_Y * 2)

    for i = 1, lineCount do
        local line = f.lines[i]
        line.left:ClearAllPoints()
        line.left:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_X, -(PAD_Y + (i - 1) * rowH))
        line.right:ClearAllPoints()
        line.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD_X, -(PAD_Y + (i - 1) * rowH))
    end
    -- Hide unused lines from any earlier longer build. Clear timerExp
    -- so the OnUpdate ticker doesn't keep stamping countdown text into
    -- a hidden line that gets reused for a non-timer line later.
    for i = lineCount + 1, #f.lines do
        f.lines[i].left:Hide()
        f.lines[i].right:Hide()
        f.lines[i].timerExp = nil
    end
end

local function setLine(f, idx, leftText, rightText, lr, lg, lb, rr, rg, rb, timerExp)
    local line = tooltipLine(f, idx)
    line.left:SetText(leftText or "")
    line.left:SetTextColor(lr or 1, lg or 1, lb or 1)
    line.left:Show()
    -- timerExp = a GetTime()-relative expiration. When set, the
    -- tooltip's OnUpdate ticker overwrites the right-side text every
    -- 0.1s with the remaining seconds; the static rightText acts as a
    -- placeholder for layout sizing during the rebuild.
    line.timerExp = timerExp
    if rightText or timerExp then
        line.right:SetText(rightText or "")
        line.right:SetTextColor(rr or 1, rg or 1, rb or 1)
        line.right:Show()
    else
        line.right:Hide()
    end
end

-- Resolve a unit's raid subgroup (1..8). Nil if not in a raid or the
-- unit isn't a raid member (party/solo, NPCs, enemy targets).
--
-- Avoids UnitInRaid: its 0-based-vs-1-based contract has shifted
-- between Classic Era patches, and an off-by-one when feeding into
-- GetRaidRosterInfo (which is firmly 1-based) returns the *next*
-- raid member's subgroup — produces a tooltip that's plausibly
-- correct but consistently wrong by one slot. Two reliable paths:
--   1. "raidN" tokens map 1:1 to the raid roster index, so we parse
--      N out and call GetRaidRosterInfo(N) directly.
--   2. "player" / "partyN" / other tokens have no direct mapping;
--      walk the roster and match by name.
function Cell.UnitSubgroup(unit)
    if not unit or not IsInRaid() then return nil end

    local n = unit:match("^raid(%d+)$")
    if n then
        local _, _, subgroup = GetRaidRosterInfo(tonumber(n))
        return subgroup
    end

    local name, realm = UnitName(unit)
    if not name then return nil end
    local full = (realm and realm ~= "") and (name .. "-" .. realm) or nil
    for i = 1, GetNumGroupMembers() do
        local rname, _, subgroup = GetRaidRosterInfo(i)
        if rname and (rname == full or rname == name) then
            return subgroup
        end
    end
    return nil
end
local unitSubgroup = Cell.UnitSubgroup

-- Resolve a unit's current zone name. Three sources:
--   1. The player unit always knows its own zone via GetRealZoneText.
--   2. Raid members surface their zone as the 7th return of
--      GetRaidRosterInfo (live, including offline players' last-known
--      zone).
--   3. Party members have no equivalent API in Classic Era — fall back
--      to the player's zone since the party is almost always grouped
--      together for instanced content.
local function unitZone(unit)
    if not unit then return nil end
    if UnitIsUnit(unit, "player") then
        return GetRealZoneText()
    end
    if IsInRaid() then
        -- Same UnitInRaid pitfall as unitSubgroup above — parse the
        -- raid index out of the unit token directly when possible,
        -- fall back to a name match for non-"raidN" tokens.
        local n = unit:match("^raid(%d+)$")
        if n then
            local _, _, _, _, _, _, zone = GetRaidRosterInfo(tonumber(n))
            return zone
        end
        local name, realm = UnitName(unit)
        if name then
            local full = (realm and realm ~= "") and (name .. "-" .. realm) or nil
            for i = 1, GetNumGroupMembers() do
                local rname, _, _, _, _, _, zone = GetRaidRosterInfo(i)
                if rname and (rname == full or rname == name) then
                    return zone
                end
            end
        end
    end
    if IsInGroup() and UnitInParty and UnitInParty(unit) then
        return GetRealZoneText()
    end
    return nil
end

local function rebuildTooltip(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    local f = ensureTooltip()
    local idx = 0

    local _, class = UnitClass(unit)
    local cc = class and RAID_CLASS_COLORS[class]
    local subgroup = unitSubgroup(unit)
    idx = idx + 1
    setLine(f, idx, UnitName(unit) or unit,
        subgroup and ("Group " .. subgroup) or nil,
        cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1,
        0.7, 0.7, 0.7)

    local zone = unitZone(unit)
    if zone and zone ~= "" then
        idx = idx + 1
        setLine(f, idx, zone, nil, 0.7, 0.7, 0.7)
    end

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if hpMax and hpMax > 0 then
        idx = idx + 1
        setLine(f, idx, ("HP: %d / %d"):format(hp, hpMax), nil, 0.8, 0.8, 0.8)
    end

    -- HoTs you've cast on this player, with a live remaining-duration
    -- timer. Same scan logic as the cell's HoT-icon overlay so what's
    -- shown here matches what the corner icons surface.
    -- The initial right-text uses the actual current remaining seconds
    -- (not a "—" placeholder) so layoutTooltip reserves enough width
    -- for the OnUpdate ticker's later writes — durations only decrease,
    -- so the format always fits.
    local now = GetTime()
    local function fmtRemain(exp)
        if not exp or exp <= 0 then return "—" end
        local r = exp - now
        if r <= 0 then return "—" end
        return ("%.1fs"):format(r)
    end

    if ns.HoT and ns.HoT.Scan then
        local hots = ns.HoT.Scan(unit)
        if #hots > 0 then
            idx = idx + 1
            setLine(f, idx, "HoTs:", nil, 0.6, 1.0, 0.6)
            for _, h in ipairs(hots) do
                idx = idx + 1
                setLine(f, idx, "  " .. h.name, fmtRemain(h.exp),
                    0.85, 1, 0.85, 0.7, 1, 0.7, h.exp)
            end
        end
    end

    -- Dispellable debuffs the player can remove. Iterates the unit's
    -- debuffs and filters by the player's class dispel set; lists all
    -- matches with their school.
    local canDispel = ns.Aura and ns.Aura.CLASS_DISPELS and ns.Aura.CLASS_DISPELS[ns.playerClass]
    if canDispel and ns.Aura and ns.Aura.getDebuff then
        local matches = {}
        for i = 1, 40 do
            local name, _, _, dt, exp = ns.Aura.getDebuff(unit, i)
            if not name then break end
            if dt and canDispel[dt] then
                table.insert(matches, { name = name, type = dt, exp = exp })
            end
        end
        if #matches > 0 then
            idx = idx + 1
            setLine(f, idx, "Dispellable:", nil, 1.0, 0.6, 0.6)
            for _, d in ipairs(matches) do
                idx = idx + 1
                -- Type moves into the left column as a parenthetical so
                -- the right column can carry the live countdown timer.
                setLine(f, idx, ("  %s (%s)"):format(d.name, d.type), fmtRemain(d.exp),
                    1, 0.85, 0.85, 1, 0.7, 0.7, d.exp)
            end
        end
    end

    -- Active defensive cooldowns on this unit, regardless of cell type.
    -- The cell's bottom-right defensive-icon overlay only paints on tank
    -- cells, but the tooltip surfaces this info for everyone — useful
    -- for spotting when a DPS pally just popped Divine Shield, etc.
    if ns.Defensives and ns.Defensives.Scan then
        local defs = ns.Defensives.Scan(unit)
        if #defs > 0 then
            idx = idx + 1
            setLine(f, idx, "Defensives:", nil, 1.0, 0.85, 0.5)
            for _, d in ipairs(defs) do
                idx = idx + 1
                setLine(f, idx, "  " .. d.name, fmtRemain(d.exp),
                    1, 0.95, 0.85, 1, 0.85, 0.6, d.exp)
            end
        end
    end

    -- Class-scoped raid buffs the viewer is responsible for casting,
    -- only listed when missing. Priest sees Fortitude / Spirit
    -- categories; Druid sees Mark. Mirrors the amber outer-ring glow
    -- on the cell when any of these are missing.
    if ns.MissingBuffs and ns.MissingBuffs.Scan then
        local missing = ns.MissingBuffs.Scan(unit)
        if #missing > 0 then
            idx = idx + 1
            setLine(f, idx, "Missing buffs:", nil, 1.0, 0.65, 0.15)
            for _, name in ipairs(missing) do
                idx = idx + 1
                setLine(f, idx, "  " .. name, nil, 1, 0.85, 0.6)
            end
        end
    end

    -- Tracked class-relevant auras (PW:S, Weakened Soul, Power Infusion,
    -- Innervate, Forbearance, BoP). Same source as the bottom-left icon
    -- row, so the tooltip stays in sync with what the cell visually
    -- shows. The set is keyed by the *viewer's* class — a Druid sees
    -- Innervate + PW:S, a Priest sees PW:S + Weakened Soul + PI, etc.
    if ns.CooldownTrack and ns.CooldownTrack.Scan then
        local tracked = ns.CooldownTrack.Scan(unit)
        if #tracked > 0 then
            idx = idx + 1
            setLine(f, idx, "Tracked:", nil, 0.7, 0.85, 1.0)
            for _, t in ipairs(tracked) do
                idx = idx + 1
                setLine(f, idx, "  " .. t.name, fmtRemain(t.exp),
                    0.85, 0.92, 1, 0.7, 0.8, 1, t.exp)
            end
        end
    end

    local mod = currentModifier()
    local bindings = ns.Bindings and ns.Bindings:Get()
    if bindings then
        idx = idx + 1
        setLine(f, idx, prettyModifier(mod), nil, 0.6, 0.8, 1)

        local matched = 0
        for i = 1, #bindings do
            local b = bindings[i]
            if b.mod == mod then
                matched = matched + 1
                -- Show what will actually cast — including the rank
                -- when the stored binding is unranked (Blizzard
                -- auto-resolves to highest known; we surface which
                -- rank that is so the tooltip doesn't make the user
                -- guess). Strip any (Rank N) from the display name
                -- and re-append from `actualRank` so we never
                -- duplicate the suffix.
                local resolved, exact, actualRank = ns.Bindings:Resolve(b.spell)
                local mana
                if resolved then _, mana = spellRankAndCost(resolved) end
                local displayName = resolved or b.spell
                local base = displayName:match("^(.-)%(Rank %d+%)$") or displayName
                local right = base
                if actualRank then right = right .. " (Rank " .. actualRank .. ")" end
                if mana and mana > 0 then right = right .. " — " .. mana .. " mana" end
                idx = idx + 1
                local btnLabel = BUTTON_NAMES[b.btn] or ("Button " .. tostring(b.btn))
                local rr, rg, rb
                if resolved and exact then     rr, rg, rb = 0.4, 1.0, 0.4   -- exact match
                elseif resolved        then     rr, rg, rb = 1.0, 0.85, 0.2 -- rank fallback
                else                            rr, rg, rb = 1.0, 0.4, 0.4  -- unknown
                end
                setLine(f, idx, btnLabel, right, 1, 1, 1, rr, rg, rb)
            end
        end
        if matched == 0 then
            idx = idx + 1
            setLine(f, idx, "(no bindings)", nil, 0.6, 0.6, 0.6)
        end
    end

    layoutTooltip(f, idx)

    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", button, "TOPRIGHT", 6, 0)
    f:Show()
end

local function showCellTooltip(button)
    hoveredButton = button
    rebuildTooltip(button)
end

local function hideCellTooltip()
    hoveredButton = nil
    if tooltip then tooltip:Hide() end
end

-- Live-update the tooltip when modifier keys are pressed/released
-- while hovering a cell. Registered at file-load time so it doesn't
-- depend on cell creation order.
ns:On("MODIFIER_STATE_CHANGED", function()
    if hoveredButton then rebuildTooltip(hoveredButton) end
end)

-- Refresh the tooltip when auras change on the unit being hovered, so
-- the dispellable-debuffs section stays current without needing to move
-- the mouse off and back on.
ns:On("UNIT_AURA", function(unit)
    if not hoveredButton then return end
    local hUnit = hoveredButton:GetAttribute("unit")
    if not hUnit then return end
    if hUnit == unit
       or ((hUnit == "target" or hUnit == "targettarget")
           and UnitExists(hUnit) and UnitIsUnit(hUnit, unit)) then
        rebuildTooltip(hoveredButton)
    end
end)

function Cell:Skin(button)
    if skinned[button] then
        Cell:Update(button)
        return
    end
    skinned[button] = true

    button:RegisterForClicks("AnyDown")
    button:SetScript("OnEnter", showCellTooltip)
    button:SetScript("OnLeave", hideCellTooltip)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.6)
    button.hbg = bg

    -- Incoming-heal preview: drawn behind hpBar so the segment beyond
    -- current health (hp..hp+incoming) shows through as green. Frame level
    -- is set explicitly so hpBar (default child level = parent+1) draws on
    -- top.
    local incomingBar = CreateFrame("StatusBar", nil, button)
    incomingBar:SetPoint("TOPLEFT", 1, -1)
    incomingBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 7)
    incomingBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    incomingBar:SetStatusBarColor(0.2, 0.9, 0.2, 1)
    incomingBar:SetMinMaxValues(0, 1)
    incomingBar:SetValue(0)
    incomingBar:SetFrameLevel(button:GetFrameLevel())
    button.incomingBar = incomingBar

    local hpBar = CreateFrame("StatusBar", nil, button)
    hpBar:SetPoint("TOPLEFT", 1, -1)
    hpBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 7)
    hpBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    hpBar:SetMinMaxValues(0, 1)
    hpBar:SetValue(1)
    button.hpBar = hpBar

    local powerBar = CreateFrame("StatusBar", nil, button)
    powerBar:SetPoint("BOTTOMLEFT", 1, 1)
    powerBar:SetPoint("BOTTOMRIGHT", -1, 1)
    powerBar:SetHeight(5)
    powerBar:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
    powerBar:SetMinMaxValues(0, 1)
    powerBar:SetValue(1)
    button.powerBar = powerBar

    -- Name spans the top of the hpBar, drawn at OVERLAY sublayer 6 so
    -- it sits ABOVE the HoT/debuff icons (sublayer 0) when their
    -- positions overlap — combined with a 1px black drop shadow this
    -- keeps the text readable when an icon is directly behind it.
    --
    -- SetWordWrap(false) + SetMaxLines(1) keep names that overflow the
    -- cell width on a single line and end with the engine's "..."
    -- truncation. Without these, multi-word names (and long single-word
    -- ones with the wrap default) wrap to a second line — and because
    -- the FontString is anchored TOPLEFT/TOPRIGHT (height grows
    -- downward), wrapping shifts the visible text off the cell's top
    -- edge.
    local nameFS = hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameFS:SetDrawLayer("OVERLAY", 6)
    nameFS:SetPoint("TOPLEFT", 2, -1)
    nameFS:SetPoint("TOPRIGHT", -2, -1)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetJustifyV("TOP")
    nameFS:SetWordWrap(false)
    if nameFS.SetMaxLines then nameFS:SetMaxLines(1) end
    nameFS:SetShadowColor(0, 0, 0, 1)
    nameFS:SetShadowOffset(1, -1)
    button.hname = nameFS

    local hpText = hpBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpText:SetPoint("BOTTOM", 0, 2)
    button.hpText = hpText

    -- Dispellable debuffs the player's class can remove. Two slots
    -- anchored top-right and growing leftward; ordered by class dispel
    -- priority (Modules/Aura.lua paints them). Two slots covers Priest
    -- / Druid / Shaman fully (max 2 dispellable schools each); Paladin
    -- can in theory have 3 simultaneous schools, but in that rare case
    -- the priority ordering picks the top 2 and the 3rd is still listed
    -- in the cell tooltip's Dispellable section.
    button.debuffIcons = {}
    for i = 1, 2 do
        local icon = hpBar:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        if i == 1 then
            icon:SetPoint("TOPRIGHT", -1, -1)
        else
            icon:SetPoint("RIGHT", button.debuffIcons[i - 1], "LEFT", -1, 0)
        end
        icon:Hide()
        button.debuffIcons[i] = icon
    end

    button.hotIcons = {}
    for i = 1, 3 do
        local icon = hpBar:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        if i == 1 then
            icon:SetPoint("TOPLEFT", 1, -1)
        else
            icon:SetPoint("LEFT", button.hotIcons[i - 1], "RIGHT", 1, 0)
        end
        icon:Hide()
        button.hotIcons[i] = icon
    end

    -- Pending-res indicator. Centered on the hpBar so it's visible at
    -- a glance regardless of cell content. Driven by
    -- INCOMING_RESURRECT_CHANGED (any res spell, not just Rebirth).
    local resIcon = hpBar:CreateTexture(nil, "OVERLAY", nil, 5)
    resIcon:SetSize(20, 20)
    resIcon:SetPoint("CENTER")
    resIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
    resIcon:Hide()
    button.resIcon = resIcon

    -- Cooldown / tracked-aura icons. Bottom-left of the hpBar, growing
    -- right. Each slot is a Frame with a texture + a Cooldown overlay
    -- for swipe + countdown text.
    button.cdIcons = {}
    for i = 1, 4 do
        local slot = CreateFrame("Frame", nil, hpBar)
        slot:SetSize(14, 14)
        if i == 1 then
            slot:SetPoint("BOTTOMLEFT", 1, 1)
        else
            slot:SetPoint("LEFT", button.cdIcons[i - 1], "RIGHT", 1, 0)
        end
        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        slot.icon = tex
        local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(false)
        -- Reverse swipe: bright area = remaining duration, dark grows
        -- inward as the buff depletes. Matches the standard buff-icon
        -- visual intuition ("watch the bright slice shrink") rather
        -- than the default cooldown swipe ("watch the dark slice
        -- shrink") which reads as elapsed time and is backwards for
        -- aura tracking.
        cd:SetReverse(true)
        slot.cooldown = cd
        slot:Hide()
        button.cdIcons[i] = slot
    end

    -- Defensive cooldown icons. Bottom-right of the hpBar, growing left
    -- (mirror of cdIcons). Painted by Modules/Defensives.lua, populated only
    -- on tank cells. Created here so any cell can host them if the rules
    -- are extended later — saves wiring up post-creation injection.
    button.defensiveIcons = {}
    for i = 1, 2 do
        local slot = CreateFrame("Frame", nil, hpBar)
        slot:SetSize(14, 14)
        if i == 1 then
            slot:SetPoint("BOTTOMRIGHT", -1, 1)
        else
            slot:SetPoint("RIGHT", button.defensiveIcons[i - 1], "LEFT", -1, 0)
        end
        local tex = slot:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        slot.icon = tex
        local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(false)
        cd:SetReverse(true)  -- bright = remaining; see cdIcons above.
        slot.cooldown = cd
        slot:Hide()
        button.defensiveIcons[i] = slot
    end

    -- Threat border: a separate frame layered above hpBar so the colored
    -- edges aren't covered by status-bar fills or icons. Four thin textures
    -- form a rectangle around the cell.
    local borderFrame = CreateFrame("Frame", nil, button)
    borderFrame:SetAllPoints(button)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + 5)
    local th = 2
    local function makeEdge(p1, p2, w, h)
        local t = borderFrame:CreateTexture(nil, "OVERLAY")
        t:SetPoint(unpack(p1))
        t:SetPoint(unpack(p2))
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        return t
    end
    button.threatBorder = {
        makeEdge({"TOPLEFT", 0, 0},        {"TOPRIGHT", 0, 0},        nil, th),
        makeEdge({"BOTTOMLEFT", 0, 0},     {"BOTTOMRIGHT", 0, 0},     nil, th),
        makeEdge({"TOPLEFT", 0, -th},      {"BOTTOMLEFT", 0, th},     th,  nil),
        makeEdge({"TOPRIGHT", 0, -th},     {"BOTTOMRIGHT", 0, th},    th,  nil),
    }

    -- Target glow: 4 additive textures forming a halo just OUTSIDE the
    -- cell. Painted by Modules/TargetGlow.lua when this cell's player is
    -- the current target. Sized as a ring around the cell so it doesn't
    -- mix with the cell's own background; additive blend so it stays
    -- subtle over whatever's behind the frames.
    local glowFrame = CreateFrame("Frame", nil, button)
    glowFrame:SetAllPoints(button)
    glowFrame:SetFrameLevel(button:GetFrameLevel() + 4)
    local gth = 3
    local function makeGlow(p1, p2, w, h)
        local t = glowFrame:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("ADD")
        t:SetPoint(unpack(p1))
        t:SetPoint(unpack(p2))
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        t:Hide()
        return t
    end
    button.targetGlow = {
        -- Top edge spans the full width including corner overlap.
        makeGlow({"BOTTOMLEFT", button, "TOPLEFT", -gth, 0},
                 {"BOTTOMRIGHT", button, "TOPRIGHT", gth, 0}, nil, gth),
        -- Bottom edge spans the full width including corner overlap.
        makeGlow({"TOPLEFT", button, "BOTTOMLEFT", -gth, 0},
                 {"TOPRIGHT", button, "BOTTOMRIGHT", gth, 0}, nil, gth),
        -- Left edge spans only the cell's height (corners covered above).
        makeGlow({"TOPRIGHT", button, "TOPLEFT", 0, 0},
                 {"BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0}, gth, nil),
        -- Right edge spans only the cell's height.
        makeGlow({"TOPLEFT", button, "TOPRIGHT", 0, 0},
                 {"BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0}, gth, nil),
    }

    -- Focus glow: same outer-ring geometry as targetGlow, painted by
    -- Modules/Focus.lua when this cell's player is on the per-character
    -- focus list (raid healing assignments). Pink instead of cyan so
    -- the two signals are independently legible; both use ADD blend so
    -- when the focused player is also your current target the colours
    -- additive-blend into a brighter halo rather than fighting for the
    -- same pixels.
    button.focusGlow = {
        makeGlow({"BOTTOMLEFT", button, "TOPLEFT", -gth, 0},
                 {"BOTTOMRIGHT", button, "TOPRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPLEFT", button, "BOTTOMLEFT", -gth, 0},
                 {"TOPRIGHT", button, "BOTTOMRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPRIGHT", button, "TOPLEFT", 0, 0},
                 {"BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0}, gth, nil),
        makeGlow({"TOPLEFT", button, "TOPRIGHT", 0, 0},
                 {"BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0}, gth, nil),
    }

    -- Triage glow: same outer-ring geometry as target/focus, painted by
    -- Modules/Triage.lua when (HP + LibHealComm-predicted incoming) /
    -- maxHP falls below the triage threshold. Pure white at high alpha
    -- so it dominates the additive stack — even when a triage cell is
    -- also your current target or assigned focus the white channel
    -- reads as "heal this NOW" through the underlying cyan/pink.
    button.triageGlow = {
        makeGlow({"BOTTOMLEFT", button, "TOPLEFT", -gth, 0},
                 {"BOTTOMRIGHT", button, "TOPRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPLEFT", button, "BOTTOMLEFT", -gth, 0},
                 {"TOPRIGHT", button, "BOTTOMRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPRIGHT", button, "TOPLEFT", 0, 0},
                 {"BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0}, gth, nil),
        makeGlow({"TOPLEFT", button, "TOPRIGHT", 0, 0},
                 {"BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0}, gth, nil),
    }

    -- Subgroup-highlight glow: same outer-ring geometry, painted by
    -- Modules/SubgroupHighlight.lua when this cell's player belongs to
    -- a subgroup flagged in HelloHealerCharDB.highlightSubgroups.
    -- Saturated blue keeps it independently legible against the cyan
    -- target / pink focus / white triage / amber missing-buffs palette,
    -- and additive-blends cleanly when those signals overlap.
    button.subgroupGlow = {
        makeGlow({"BOTTOMLEFT", button, "TOPLEFT", -gth, 0},
                 {"BOTTOMRIGHT", button, "TOPRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPLEFT", button, "BOTTOMLEFT", -gth, 0},
                 {"TOPRIGHT", button, "BOTTOMRIGHT", gth, 0}, nil, gth),
        makeGlow({"TOPRIGHT", button, "TOPLEFT", 0, 0},
                 {"BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0}, gth, nil),
        makeGlow({"TOPLEFT", button, "TOPRIGHT", 0, 0},
                 {"BOTTOMLEFT", button, "BOTTOMRIGHT", 0, 0}, gth, nil),
    }

    -- Missing-buffs indicator: a 3 px solid amber bar in the column
    -- gap to the LEFT of the cell, full cell height. Lives outside
    -- the cell's left edge so it doesn't compete with cell content;
    -- vertical neighbours each have their own bar separated by the
    -- 2 px row gap, so there's no overlap or doubling. Solid colour
    -- (no additive blend) so the bar reads consistently regardless
    -- of what the WoW world is showing behind the raid frames. For
    -- column-1 cells and tank cells the bar extends into the open
    -- space to the left of the addon, which actually makes it more
    -- visible there. Painted by Modules/MissingBuffs.lua.
    local missingFrame = CreateFrame("Frame", nil, button)
    missingFrame:SetAllPoints(button)
    missingFrame:SetFrameLevel(button:GetFrameLevel() + 3)
    local missingBar = missingFrame:CreateTexture(nil, "OVERLAY")
    missingBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    missingBar:SetPoint("TOPRIGHT",    button, "TOPLEFT",    0, 0)
    missingBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMLEFT", 0, 0)
    missingBar:SetWidth(3)
    missingBar:Hide()
    -- Single-element array so MissingBuffs.lua's setGlow loop, which
    -- iterates the table to support multi-texture indicators, keeps
    -- working unchanged.
    button.missingBuffGlow = { missingBar }

    -- Deliberately NOT using HookScript on OnAttributeChanged or OnShow.
    -- Hooks on secure frames run inside Blizzard's secure call stack and
    -- propagate addon taint to the shared aura subsystem, which breaks
    -- DragonflightUI's BuffFrame in combat. Cell paint is driven entirely
    -- via the event dispatcher (UNIT_HEALTH, GROUP_ROSTER_UPDATE, etc.).

    ns.ClickCast:ApplyTo(button)
    Cell:Update(button)
end

function Cell:Update(button)
    local unit = button:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    button.hname:SetText(UnitName(unit) or "")

    if UnitIsConnected(unit) == false then
        -- Offline: gray bar, full, no HP delta — last-known HP is
        -- meaningless and a partial bar would suggest the player still
        -- needs heals.
        button.hpBar:SetStatusBarColor(0.4, 0.4, 0.4)
        button.hpBar:SetValue(1)
        button.hpText:SetText("")
        return
    end

    local _, class = UnitClass(unit)
    local c = class and RAID_CLASS_COLORS[class]
    if c then
        button.hpBar:SetStatusBarColor(c.r, c.g, c.b)
    else
        button.hpBar:SetStatusBarColor(0.5, 0.5, 0.5)
    end

    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if hpMax and hpMax > 0 then
        button.hpBar:SetValue(hp / hpMax)
        if hp >= hpMax then
            button.hpText:SetText("")
        else
            button.hpText:SetText("-" .. (hpMax - hp))
        end
    end
end

function Cell:UpdateUnit(unit)
    Cell:ForEachCellForUnit(unit, function(b) Cell:Update(b) end)
end

-- Iterate every cell whose displayed unit matches `unit`, including
-- alias cells (target / targettarget) that may currently point to that
-- same player. UNIT_* events fire with the canonical unit ID (e.g.
-- "party2"), so without this aliasing, the target / ToT cells never
-- repaint when the underlying player's state changes.
function Cell:ForEachCellForUnit(unit, fn)
    if not unit then return end
    for button in pairs(skinned) do
        local childUnit = button:GetAttribute("unit")
        if childUnit then
            if childUnit == unit then
                fn(button)
            elseif (childUnit == "target" or childUnit == "targettarget")
                   and UnitExists(childUnit)
                   and UnitIsUnit(childUnit, unit) then
                fn(button)
            end
        end
    end
end

function Cell:ForEach(fn)
    -- Iterate the skinned set directly so we cover every cell we've
    -- attached visuals to, not just the main header's children. This
    -- includes tank-header cells and target/ToT cells.
    for button in pairs(skinned) do
        if button:GetAttribute("unit") then
            fn(button)
        end
    end
end

function Cell:FindByUnit(unit)
    if not unit or not ns.Header or not ns.Header.columns then return nil end
    for i = 1, #ns.Header.columns do
        local children = { ns.Header.columns[i]:GetChildren() }
        for j = 1, #children do
            local child = children[j]
            if child:GetAttribute("unit") == unit then
                return child
            end
        end
    end
    if ns.Header.petColumn then
        local children = { ns.Header.petColumn:GetChildren() }
        for j = 1, #children do
            local child = children[j]
            if child:GetAttribute("unit") == unit then
                return child
            end
        end
    end
    return nil
end

Cell.WIDTH  = CELL_WIDTH
Cell.HEIGHT = CELL_HEIGHT
