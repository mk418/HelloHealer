local ADDON_NAME, ns = ...

ns.Settings = {}
local S = ns.Settings

local BTN_NAMES  = { "left", "right", "middle", "mouse4", "mouse5" }
local BTN_FROM_NAME = {
    left = 1, right = 2, middle = 3, mouse4 = 4, mouse5 = 5,
    ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
}

local function comboLabel(b)
    local mod = (b.mod ~= "" and (b.mod .. "-")) or ""
    return mod .. (BTN_NAMES[b.btn] or ("btn" .. b.btn))
end

-- Parse a combo string like "left", "shift-left", "ctrl-shift-right".
-- Returns (btn, canonicalMod) on success, nil on bad input. Canonical
-- modifier order is alt-ctrl-shift, matching the SecureUnitButton
-- attribute prefix order.
local function parseCombo(combo)
    if not combo or combo == "" then return nil end
    local parts = {}
    for tok in combo:gmatch("[^%-]+") do table.insert(parts, tok:lower()) end
    if #parts == 0 then return nil end
    local btnName = parts[#parts]
    local btn = BTN_FROM_NAME[btnName]
    if not btn then return nil end
    local has = {}
    for i = 1, #parts - 1 do
        local m = parts[i]
        if m == "alt" or m == "ctrl" or m == "shift" then
            has[m] = true
        else
            return nil
        end
    end
    local modParts = {}
    if has.alt   then table.insert(modParts, "alt")   end
    if has.ctrl  then table.insert(modParts, "ctrl")  end
    if has.shift then table.insert(modParts, "shift") end
    return btn, table.concat(modParts, "-")
end

-- Order modifiers as: none, then by number of modifiers, then alpha.
-- Keeps simpler bindings on top in the panel.
local function modWeight(mod)
    if mod == "" then return 0 end
    local n = 0
    for _ in mod:gmatch("[^%-]+") do n = n + 1 end
    return n * 10 + (mod:byte(1) or 0) -- arbitrary but stable
end

local function sortBindings(list)
    table.sort(list, function(a, b)
        if a.btn ~= b.btn then return a.btn < b.btn end
        return modWeight(a.mod) < modWeight(b.mod)
    end)
    return list
end

local function makeCheckButton(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    if cb.Text then
        cb.Text:SetText(label)
    else
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        fs:SetText(label)
    end
    return cb
end

local function makeButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetText(label)
    b:SetSize(w or 160, 24)
    return b
end

local function makeHeader(parent, label)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(label)
    return fs
end

local function makeBody(parent)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWidth(540)
    return fs
end

-- Combat-gating helpers --------------------------------------------------------
-- Any control whose effect runs through the secure environment
-- (click-cast attribute writes, tank-header nameList edits, scale changes
-- on the SecureGroupHeader, frame Reposition) is unsafe to fire during
-- combat lockdown. The underlying layers already defer or no-op, but
-- the panel itself shouldn't pretend the input was accepted — instead
-- it greys out and explains. Lock checkbox + "Reset everything (reload)"
-- are deliberately NOT gated; the lock state is a non-secure local
-- toggle, and ReloadUI works in combat.

local function setControlEnabled(ctrl, enabled)
    local t = ctrl:GetObjectType()
    if t == "EditBox" then
        if enabled then
            ctrl:EnableMouse(true)
            ctrl:EnableKeyboard(true)
            ctrl:SetTextColor(1, 1, 1)
        else
            ctrl:ClearFocus()
            ctrl:EnableMouse(false)
            ctrl:EnableKeyboard(false)
            ctrl:SetTextColor(0.5, 0.5, 0.5)
        end
    else  -- Button, Slider, CheckButton — all support Enable/Disable
        if enabled then ctrl:Enable() else ctrl:Disable() end
    end
end

local function attachCombatTooltip(ctrl)
    -- Disabled mouse-enabled controls (Buttons, Sliders) still fire
    -- OnEnter/OnLeave; EditBoxes lose mouse when disabled, so tooltips
    -- on them won't fire in combat — fine, the surrounding buttons in
    -- the same row carry the explanation and the visual grey is enough
    -- on its own.
    local origEnter = ctrl:GetScript("OnEnter")
    local origLeave = ctrl:GetScript("OnLeave")
    ctrl:SetScript("OnEnter", function(self)
        if InCombatLockdown() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Disabled during combat", 1, 0.85, 0.5)
            GameTooltip:AddLine(
                "Click-cast bindings, the tank list, and frame layout " ..
                "touch secure attributes that the WoW client locks " ..
                "during combat. These controls re-enable when combat ends.",
                1, 1, 1, true)
            GameTooltip:Show()
        elseif origEnter then
            origEnter(self)
        end
    end)
    ctrl:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if origLeave then origLeave(self) end
    end)
end

local function buildTankRow(parent, name)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 22)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(340)
    label:SetJustifyH("LEFT")
    label:SetText(name)

    local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    remove:SetSize(70, 22)
    remove:SetText("Remove")
    remove:SetPoint("LEFT", label, "RIGHT", 12, 0)
    remove:SetScript("OnClick", function()
        local list = HelloHealerCharDB.tankList
        for i, n in ipairs(list) do
            if n == name then
                table.remove(list, i)
                break
            end
        end
        if ns.TankHeader and ns.TankHeader.RefreshNameList then
            ns.TankHeader:RefreshNameList()
        end
        S:RefreshTankList()
    end)

    -- Secure: TankHeader.RefreshNameList rewrites the secure
    -- header's nameList attribute, which is combat-blocked.
    row.gatedControls = { remove }
    return row
end

local function buildTankAddRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 22)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(60)
    label:SetJustifyH("LEFT")
    label:SetText("New:")

    local nameEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    nameEdit:SetSize(270, 20)
    nameEdit:SetPoint("LEFT", label, "RIGHT", 12, 0)
    nameEdit:SetAutoFocus(false)

    local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 22)
    addBtn:SetText("Add")
    addBtn:SetPoint("LEFT", nameEdit, "RIGHT", 12, 0)

    local function add()
        local name = nameEdit:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            -- Same fallback as `/hh tank` with no arg: take the current target
            -- if it's a friendly player, with the cross-realm full name.
            if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target")
               and ns.TankHeader and ns.TankHeader.FullName then
                name = ns.TankHeader.FullName("target")
            else
                print("|cff80ff80HelloHealer|r enter a name, or target a friendly player")
                return
            end
        elseif ns.TankHeader and ns.TankHeader.ResolveName then
            name = ns.TankHeader:ResolveName(name)
        end
        local list = HelloHealerCharDB.tankList
        for _, existing in ipairs(list) do
            if existing:lower() == name:lower() then
                print("|cff80ff80HelloHealer|r already in tank list: " .. existing)
                return
            end
        end
        table.insert(list, name)
        if ns.TankHeader and ns.TankHeader.RefreshNameList then
            ns.TankHeader:RefreshNameList()
        end
        nameEdit:SetText("")
        S:RefreshTankList()
    end

    addBtn:SetScript("OnClick", add)
    nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); add() end)

    -- Hint text inside the edit box when empty + unfocused.
    local hint = nameEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 4, 0)
    hint:SetText("name (or leave empty to use your target)")
    local function updateHint()
        if nameEdit:GetText() == "" and not nameEdit:HasFocus() then
            hint:Show()
        else
            hint:Hide()
        end
    end
    nameEdit:SetScript("OnEditFocusGained", function() hint:Hide() end)
    nameEdit:SetScript("OnEditFocusLost",   updateHint)
    nameEdit:SetScript("OnTextChanged",     updateHint)
    updateHint()

    row.gatedControls = { nameEdit, addBtn }
    return row
end

local function buildBindingRow(parent, b)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 24)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(110)
    label:SetJustifyH("LEFT")
    label:SetText(comboLabel(b))

    local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    edit:SetSize(220, 20)
    edit:SetPoint("LEFT", label, "RIGHT", 12, 0)
    edit:SetAutoFocus(false)
    edit:SetText(b.spell)

    local clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    clear:SetSize(60, 22)
    clear:SetText("Clear")
    clear:SetPoint("LEFT", edit, "RIGHT", 12, 0)

    local function save()
        local newSpell = edit:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if newSpell == b.spell then return end
        if newSpell ~= "" and not GetSpellInfo(newSpell) then
            print(("|cff80ff80HelloHealer|r unknown spell: %q (binding not saved)"):format(newSpell))
            edit:SetText(b.spell)
            return
        end
        if newSpell == "" then
            ns.Bindings:Unset(b.btn, b.mod)
        else
            ns.Bindings:Set(b.btn, b.mod, newSpell)
        end
        if ns.ClickCast then ns.ClickCast:ApplyAll() end
        S:RefreshBindings()
    end

    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); save() end)
    edit:SetScript("OnEscapePressed", function(self) self:SetText(b.spell); self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", save)

    clear:SetScript("OnClick", function()
        ns.Bindings:Unset(b.btn, b.mod)
        if ns.ClickCast then ns.ClickCast:ApplyAll() end
        S:RefreshBindings()
    end)

    -- Secure: ClickCast:ApplyAll writes click-cast attributes via the
    -- combat queue; the panel still gates the input so the user
    -- doesn't think their edit took effect mid-fight.
    row.gatedControls = { edit, clear }
    return row
end

local function buildAddRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(540, 24)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(110)
    label:SetJustifyH("LEFT")
    label:SetText("New:")

    local comboEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    comboEdit:SetSize(90, 20)
    comboEdit:SetPoint("LEFT", label, "RIGHT", 12, 0)
    comboEdit:SetAutoFocus(false)

    local sep = row:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    sep:SetPoint("LEFT", comboEdit, "RIGHT", 6, 0)
    sep:SetText("->")

    local spellEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    spellEdit:SetSize(220, 20)
    spellEdit:SetPoint("LEFT", sep, "RIGHT", 6, 0)
    spellEdit:SetAutoFocus(false)

    local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetText("Add")
    addBtn:SetPoint("LEFT", spellEdit, "RIGHT", 12, 0)

    local function add()
        local combo = comboEdit:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        local spell = spellEdit:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if combo == "" or spell == "" then return end
        local btn, mod = parseCombo(combo)
        if not btn then
            print("|cff80ff80HelloHealer|r invalid combo: " .. combo .. "  (try left, shift-left, ctrl-right, mouse4, ...)")
            return
        end
        if not GetSpellInfo(spell) then
            print(("|cff80ff80HelloHealer|r unknown spell: %q (binding not saved)"):format(spell))
            return
        end
        ns.Bindings:Set(btn, mod, spell)
        if ns.ClickCast then ns.ClickCast:ApplyAll() end
        comboEdit:SetText("")
        spellEdit:SetText("")
        S:RefreshBindings()
    end

    addBtn:SetScript("OnClick", add)
    spellEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); add() end)
    comboEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); spellEdit:SetFocus() end)

    -- Combo-format hint as placeholder. EditBox doesn't have native
    -- placeholder support; show it as a faint text inside the field
    -- when empty + unfocused.
    local hint = comboEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 4, 0)
    hint:SetText("ctrl-shift-left")
    local function updateHint()
        if comboEdit:GetText() == "" and not comboEdit:HasFocus() then
            hint:Show()
        else
            hint:Hide()
        end
    end
    comboEdit:SetScript("OnEditFocusGained", function() hint:Hide() end)
    comboEdit:SetScript("OnEditFocusLost",   updateHint)
    comboEdit:SetScript("OnTextChanged",     updateHint)
    updateHint()

    row.gatedControls = { comboEdit, spellEdit, addBtn }
    return row
end

-- Recompute the scroll-content height to fit the bindings container,
-- which is the bottom-most element. Run after either container
-- changes height so the scrollbar tracks the actual content extent.
local function updateContentHeight()
    local panel = S.panel
    if not panel or not panel.content or not panel.bindingsContainer then return end
    local content = panel.content
    local container = panel.bindingsContainer
    local cTop = content:GetTop()
    local bBot = container:GetBottom()
    if cTop and bBot then
        local needed = (cTop - bBot) + 24
        content:SetHeight(needed)
    end
end

function S:RefreshTankList()
    local panel = self.panel
    if not panel or not panel.tankContainer then return end

    local container = panel.tankContainer
    if container.rows then
        for _, row in ipairs(container.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    container.rows = {}
    -- Reset and rebuild the gated-control list for this container —
    -- the per-tank row controls are destroyed/recreated on every
    -- refresh, so combat-state needs to track the current set.
    container.gated = {}

    local list = HelloHealerCharDB and HelloHealerCharDB.tankList or {}
    local rowH = 24

    for i, name in ipairs(list) do
        local row = buildTankRow(container, name)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        table.insert(container.rows, row)
        if row.gatedControls then
            for _, ctrl in ipairs(row.gatedControls) do
                table.insert(container.gated, ctrl)
                attachCombatTooltip(ctrl)
            end
        end
    end

    if not container.addRow then
        container.addRow = buildTankAddRow(container)
        if container.addRow.gatedControls then
            for _, ctrl in ipairs(container.addRow.gatedControls) do
                attachCombatTooltip(ctrl)
            end
        end
    end
    if container.addRow.gatedControls then
        for _, ctrl in ipairs(container.addRow.gatedControls) do
            table.insert(container.gated, ctrl)
        end
    end
    container.addRow:ClearAllPoints()
    container.addRow:SetPoint("TOPLEFT", 0, -(#list * rowH + 4))
    container.addRow:Show()

    container:SetHeight(#list * rowH + rowH + 8)
    updateContentHeight()
    S:RefreshCombatState()
end

function S:RefreshBindings()
    local panel = self.panel
    if not panel or not panel.bindingsContainer then return end

    local container = panel.bindingsContainer
    if container.rows then
        for _, row in ipairs(container.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    container.rows = {}
    container.gated = {}

    local list = ns.Bindings and ns.Bindings:Get() or {}
    sortBindings(list)

    local rowH = 26
    for i, b in ipairs(list) do
        local row = buildBindingRow(container, b)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        table.insert(container.rows, row)
        if row.gatedControls then
            for _, ctrl in ipairs(row.gatedControls) do
                table.insert(container.gated, ctrl)
                attachCombatTooltip(ctrl)
            end
        end
    end

    if not container.addRow then
        container.addRow = buildAddRow(container)
        if container.addRow.gatedControls then
            for _, ctrl in ipairs(container.addRow.gatedControls) do
                attachCombatTooltip(ctrl)
            end
        end
    end
    if container.addRow.gatedControls then
        for _, ctrl in ipairs(container.addRow.gatedControls) do
            table.insert(container.gated, ctrl)
        end
    end
    container.addRow:ClearAllPoints()
    container.addRow:SetPoint("TOPLEFT", 0, -(#list * rowH + 8))
    container.addRow:Show()

    container:SetHeight((#list + 1) * rowH + 12)
    updateContentHeight()
    S:RefreshCombatState()
end

-- Sweep every gated control (static + the two dynamic containers') and
-- enable/disable based on combat lockdown. Called from OnShow, after
-- each Refresh*, and on PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED.
function S:RefreshCombatState()
    local panel = self.panel
    if not panel then return end
    local enabled = not InCombatLockdown()
    local function applyList(list)
        if not list then return end
        for _, ctrl in ipairs(list) do
            setControlEnabled(ctrl, enabled)
        end
    end
    applyList(panel.staticGated)
    if panel.tankContainer     then applyList(panel.tankContainer.gated)     end
    if panel.bindingsContainer then applyList(panel.bindingsContainer.gated) end
end

function S:Build()
    if self.panel then return end

    local panel = CreateFrame("Frame")
    panel.name = "HelloHealer"
    panel.staticGated = {}

    -- Footer note pinned to the canvas so it always stays visible at
    -- the bottom while the rest of the content scrolls.
    local bindNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    bindNote:SetPoint("BOTTOMLEFT", 24, 12)
    bindNote:SetPoint("BOTTOMRIGHT", -24, 12)
    bindNote:SetJustifyH("LEFT")
    bindNote:SetText("Combo: <button> or one or more modifiers + <button>, e.g. left, shift-left, ctrl-shift-right. Modifiers: shift, ctrl, alt. Buttons: left, right, middle, mouse4, mouse5.")

    -- Scroll wrapper so growing content (bindings list, tank list)
    -- doesn't overflow the canvas.
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 36)
    panel.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540, 600)
    scroll:SetScrollChild(content)
    panel.content = content

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8)
    title:SetText("HelloHealer")

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetText("Lean, opinionated healing UI for Priest, Druid, Paladin")

    local y = -60

    local lockCb = makeCheckButton(content, "Lock frames")
    lockCb:SetPoint("TOPLEFT", 16, y)
    lockCb:SetScript("OnClick", function(self)
        HelloHealerCharDB.locked = self:GetChecked() and true or false
        if ns.Header and ns.Header.RefreshMover then ns.Header:RefreshMover() end
    end)

    -- Pet column toggle. The pet header itself is built unconditionally
    -- in Header:Create; this checkbox just flips the saved flag and
    -- calls ApplyShowPets, which is combat-gated internally.
    local petsCb = makeCheckButton(content, "Show pet frames")
    petsCb:SetPoint("LEFT", lockCb, "RIGHT", 140, 0)
    petsCb:SetScript("OnClick", function(self)
        HelloHealerCharDB.showPets = self:GetChecked() and true or false
        if ns.Header and ns.Header.ApplyShowPets then ns.Header:ApplyShowPets() end
    end)
    table.insert(panel.staticGated, petsCb)
    attachCombatTooltip(petsCb)
    panel.petsCb = petsCb
    y = y - 32

    -- Scale slider (uses OptionsSliderTemplate which provides Low/High
    -- text labels and a centered numeric value label). SetScale on
    -- protected frames is combat-blocked, so the slider's effect is
    -- deferred to combat end automatically via Header:ApplyScale.
    local scaleSlider = CreateFrame("Slider", "HelloHealerScaleSlider", content, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", 20, y - 14)
    scaleSlider:SetWidth(220)
    scaleSlider:SetMinMaxValues(0.6, 1.6)
    scaleSlider:SetValueStep(0.05)
    scaleSlider:SetObeyStepOnDrag(true)
    if scaleSlider.Low  then scaleSlider.Low:SetText("0.6") end
    if scaleSlider.High then scaleSlider.High:SetText("1.6") end
    if scaleSlider.Text then scaleSlider.Text:SetText("Frame scale") end
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        -- Snap to step (OnValueChanged is called with raw float value).
        value = math.floor(value * 20 + 0.5) / 20
        if scaleSlider.valueLabel then
            scaleSlider.valueLabel:SetText(("%.2f"):format(value))
        end
        HelloHealerDB.layout = HelloHealerDB.layout or {}
        if HelloHealerDB.layout.scale == value then return end
        HelloHealerDB.layout.scale = value
        if ns.Header and ns.Header.ApplyScale then ns.Header:ApplyScale() end
    end)
    -- Numeric current-value display next to the slider
    local valueLabel = scaleSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueLabel:SetPoint("LEFT", scaleSlider, "RIGHT", 12, 0)
    scaleSlider.valueLabel = valueLabel
    panel.scaleSlider = scaleSlider
    table.insert(panel.staticGated, scaleSlider)
    attachCombatTooltip(scaleSlider)
    y = y - 50

    local resetPos = makeButton(content, "Reset position")
    resetPos:SetPoint("TOPLEFT", 16, y)
    resetPos:SetScript("OnClick", function()
        local d = ns.Config.defaultPosition
        HelloHealerCharDB.position.point = d.point
        HelloHealerCharDB.position.x     = d.x
        HelloHealerCharDB.position.y     = d.y
        if ns.Header and ns.Header.frame then
            ns.Header.frame:ClearAllPoints()
            ns.Header.frame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
        end
    end)
    table.insert(panel.staticGated, resetPos)
    attachCombatTooltip(resetPos)

    local resetBindings = makeButton(content, "Use default bindings")
    resetBindings:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
    resetBindings:SetScript("OnClick", function()
        HelloHealerCharDB.bindings = {}
        if ns.ClickCast then ns.ClickCast:ApplyAll() end
        S:RefreshBindings()
    end)
    table.insert(panel.staticGated, resetBindings)
    attachCombatTooltip(resetBindings)

    local resetAll = makeButton(content, "Reset everything (reload)")
    resetAll:SetPoint("LEFT", resetBindings, "RIGHT", 8, 0)
    resetAll:SetScript("OnClick", function()
        HelloHealerDB = nil
        HelloHealerCharDB = nil
        ReloadUI()
    end)
    y = y - 36

    -- Editable tank list (only the manual-list portion; raid /maintank
    -- and role=TANK assignments still flow in automatically). The
    -- container's height is dynamic, so the bindings section below
    -- anchors to its bottom.
    local tankH = makeHeader(content, "Manual tank list")
    tankH:SetPoint("TOPLEFT", 16, y)

    local tankNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tankNote:SetPoint("LEFT", tankH, "RIGHT", 12, 0)
    tankNote:SetText("(raid /maintank and role=TANK assignments are added automatically)")

    local tankContainer = CreateFrame("Frame", nil, content)
    tankContainer:SetPoint("TOPLEFT", tankH, "BOTTOMLEFT", 8, -6)
    tankContainer:SetWidth(540)
    panel.tankContainer = tankContainer

    -- Editable bindings, anchored below the tank container so it reflows
    -- as tanks are added/removed.
    local bindH = makeHeader(content, "Click-cast bindings")
    bindH:SetPoint("TOPLEFT", tankContainer, "BOTTOMLEFT", -8, -16)
    panel.bindingsHeader = bindH

    local container = CreateFrame("Frame", nil, content)
    container:SetPoint("TOPLEFT", bindH, "BOTTOMLEFT", 8, -6)
    container:SetSize(540, 400)
    panel.bindingsContainer = container

    panel:SetScript("OnShow", function()
        lockCb:SetChecked(HelloHealerCharDB.locked and true or false)
        petsCb:SetChecked(HelloHealerCharDB.showPets and true or false)
        local s = (HelloHealerDB.layout and HelloHealerDB.layout.scale) or 1.0
        scaleSlider:SetValue(s)
        valueLabel:SetText(("%.2f"):format(s))
        S:RefreshTankList()
        S:RefreshBindings()
        -- The Refresh* calls already trigger RefreshCombatState, but
        -- call once more in case neither container had any rows to
        -- iterate (fresh saved-vars case).
        S:RefreshCombatState()
    end)

    -- Live combat-state tracking. Re-evaluating on every combat
    -- transition keeps the panel honest if the user leaves it open
    -- and steps into / out of combat.
    if ns and ns.On then
        ns:On("PLAYER_REGEN_DISABLED", function() S:RefreshCombatState() end)
        ns:On("PLAYER_REGEN_ENABLED",  function() S:RefreshCombatState() end)
    end

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
        self.category = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    self.panel = panel
end

function S:Open()
    if not self.panel then self:Build() end
    if Settings and Settings.OpenToCategory and self.category then
        Settings.OpenToCategory(self.category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(self.panel)
        InterfaceOptionsFrame_OpenToCategory(self.panel)
    end
end
