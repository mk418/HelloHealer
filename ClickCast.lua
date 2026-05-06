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

local function applyNow(button)
    local bindings = ns.Bindings and ns.Bindings:Get()
    if not bindings then return end

    -- Wipe previously-set click attributes so removed bindings don't
    -- linger on the cell.
    clearAppliedAttrs(button)
    local attrs = {}
    for i = 1, #bindings do
        local b = bindings[i]
        -- Skip bindings whose spell the character doesn't know — leaving
        -- a click bound to an unknown spell silently fails on click,
        -- which is confusing. The tooltip surfaces unknown ones in red
        -- so the user can see they're unbindable.
        if GetSpellInfo(b.spell) then
            local prefix = (b.mod ~= "" and (b.mod .. "-")) or ""
            local typeAttr  = prefix .. "type" .. b.btn
            local macroAttr = prefix .. "macrotext" .. b.btn
            -- type=macro with [@mouseover] gives a clean "Out of range" failure
            -- and no pending cursor cast. type=spell goes pending instead.
            button:SetAttribute(typeAttr,  "macro")
            button:SetAttribute(macroAttr, "/cast [@mouseover, exists, help] " .. b.spell)
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
