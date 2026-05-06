local ADDON_NAME, ns = ...

ns.TargetCells = {}
local TC = ns.TargetCells

local function makeButton(name, parent, unit)
    local btn = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
    btn:SetWidth(ns.Cell.WIDTH)
    btn:SetHeight(ns.Cell.HEIGHT)
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("*type1", "macro")
    RegisterUnitWatch(btn)
    return btn
end

function TC:Create()
    if not ns.Header.frame then return end

    local target = makeButton("HelloHealerTargetCell", ns.Header.frame, "target")
    target:SetPoint("BOTTOMLEFT", ns.Header.frame, "TOPLEFT", 0, 4)
    self.target = target

    local tot = makeButton("HelloHealerToTCell", ns.Header.frame, "targettarget")
    tot:SetPoint("LEFT", target, "RIGHT", 4, 0)
    self.tot = tot

    -- Skin both with the standard cell visuals + click-cast bindings.
    ns.Cell:Skin(target)
    ns.Cell:Skin(tot)

    self:ApplyBindings()

    local function repaint(button)
        ns.Cell:Update(button)
        if ns.Aura          and ns.Aura.Paint          then ns.Aura.Paint(button)          end
        if ns.Power         and ns.Power.Paint         then ns.Power.Paint(button)         end
        if ns.Range         and ns.Range.Paint         then ns.Range.Paint(button)         end
        if ns.HoT           and ns.HoT.Paint           then ns.HoT.Paint(button)           end
        if ns.Threat        and ns.Threat.Paint        then ns.Threat.Paint(button)        end
        if ns.IncomingHeal  and ns.IncomingHeal.Paint  then ns.IncomingHeal.Paint(button)  end
        if ns.CooldownTrack and ns.CooldownTrack.Paint then ns.CooldownTrack.Paint(button) end
        if ns.PendingRes    and ns.PendingRes.Paint    then ns.PendingRes.Paint(button)    end
    end

    ns:On("PLAYER_TARGET_CHANGED", function()
        repaint(target)
        repaint(tot)
    end)

    ns:On("UNIT_TARGET", function(unit)
        if unit == "target" or unit == "player" then
            repaint(tot)
        end
    end)

    -- HP / power / aura changes for the target unit feed through the
    -- existing event modules already (they handle "target" and "targettarget"
    -- via isRelevant filters), so no extra wiring needed.
end

-- Apply the current bindings to the target cell with the
-- target/@targettarget fall-through macrotext. Called from Create() at
-- setup, and from ClickCast:ApplyAll when the user changes a binding.
-- ToT cell uses the regular ClickCast path (covered by ApplyAll), since
-- it just needs the basic [@mouseover] macro.
function TC:ApplyBindings()
    if InCombatLockdown() then return end
    local bindings = ns.Bindings and ns.Bindings:Get()
    if not bindings or not self.target then return end
    for i = 1, #bindings do
        local b = bindings[i]
        if GetSpellInfo(b.spell) then
            local prefix = (b.mod ~= "" and (b.mod .. "-")) or ""
            self.target:SetAttribute(prefix .. "type" .. b.btn, "macro")
            self.target:SetAttribute(prefix .. "macrotext" .. b.btn,
                ("/cast [@target, exists, help] %s; [@targettarget, exists, help] %s")
                    :format(b.spell, b.spell))
        end
    end
end
