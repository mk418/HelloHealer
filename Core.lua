local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME

ns.eventFrame = CreateFrame("Frame")
ns.eventHandlers = {}

-- Single gate for the whole addon. ADDON_LOADED + PLAYER_LOGIN always
-- fire — they're how we read saved variables and decide whether to
-- enable. After PLAYER_LOGIN any other event is dispatched only when
-- ns.enabled is true (set below for Priest/Druid/Paladin only). This
-- means non-healer classes get the Blizzard / DragonflightUI frames
-- entirely untouched — none of the suppress hooks, paint passes, or
-- skin loops run for them.
ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" and not ns.enabled then
        return
    end
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        handlers[i](...)
    end
end)

function ns:On(event, fn)
    if not ns.eventHandlers[event] then
        ns.eventHandlers[event] = {}
        ns.eventFrame:RegisterEvent(event)
    end
    table.insert(ns.eventHandlers[event], fn)
end

ns.eventFrame:RegisterEvent("ADDON_LOADED")
ns.eventFrame:RegisterEvent("PLAYER_LOGIN")

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    ns.Config:Init()
end)

ns:On("PLAYER_LOGIN", function()
    local _, class = UnitClass("player")
    ns.playerClass = class

    if not ns.Bindings.defaults[class] then
        return
    end

    ns.enabled = true
    ns.BlizzardFrames:Hide()
    ns.Header:Create()
    ns.TankHeader:Create()
    ns.TargetCells:Create()
    ns.Header:ApplyScale()
    if ns.Settings and ns.Settings.Build then ns.Settings:Build() end

    local conflict = ns.BlizzardFrames:DetectedConflict()
    if conflict then
        print(("|cff80ff80HelloHealer|r loaded for %s (party-frame suppression skipped: %s detected)")
            :format(class, conflict))
    else
        print("|cff80ff80HelloHealer|r loaded for " .. class)
    end
end)

SLASH_HELLOHEALER1 = "/hh"
SLASH_HELLOHEALER2 = "/hellohealer"
SlashCmdList["HELLOHEALER"] = function(msg)
    local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    msg = raw:lower()
    if msg == "lock" then
        HelloHealerCharDB.locked = not HelloHealerCharDB.locked
        if ns.Header.RefreshMover then ns.Header:RefreshMover() end
        print("|cff80ff80HelloHealer|r lock = " .. tostring(HelloHealerCharDB.locked))
    elseif msg == "reset" then
        HelloHealerDB = nil
        HelloHealerCharDB = nil
        ReloadUI()
    elseif msg == "resetpos" then
        local d = ns.Config.defaultPosition
        HelloHealerCharDB.position.point = d.point
        HelloHealerCharDB.position.x     = d.x
        HelloHealerCharDB.position.y     = d.y
        if ns.Header.frame then
            ns.Header.frame:ClearAllPoints()
            ns.Header.frame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
        end
        print("|cff80ff80HelloHealer|r position reset")
    elseif msg:match("^scanbuffs") then
        local unit = msg:match("^scanbuffs%s+(%S+)") or "player"
        if not UnitExists(unit) then
            print("|cff80ff80HelloHealer|r unit not found: " .. unit)
            return
        end
        if not ns.HoTGetBuff then
            print("|cff80ff80HelloHealer|r HoT module not loaded")
            return
        end
        local found = false
        for i = 1, 40 do
            local name, icon, source, spellId = ns.HoTGetBuff(unit, i)
            if not name then break end
            found = true
            print(("[%d] %s  spellId=%s  source=%s")
                :format(i, tostring(name), tostring(spellId), tostring(source)))
        end
        if not found then print(("(no buffs on %s)"):format(unit)) end
    elseif msg == "scandebuffs" then
        if not ns.Aura or not ns.Aura.getDebuff then
            print("|cff80ff80HelloHealer|r Aura module missing")
            return
        end
        local found = false
        for i = 1, 40 do
            local name, icon, count, dt = ns.Aura.getDebuff("player", i)
            if not name then break end
            found = true
            print(("[%d] %s  type=%s  icon=%s")
                :format(i, tostring(name), tostring(dt), tostring(icon)))
        end
        if not found then print("(no debuffs on player)") end
    elseif msg == "testdebuff" then
        local cell = ns.Cell:FindByUnit("player")
        if not cell or not cell.debuffIcons then
            print("|cff80ff80HelloHealer|r no player cell found")
            return
        end
        local icon = cell.debuffIcons[1]
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:Show()
        C_Timer.After(5, function() icon:Hide() end)
        print("|cff80ff80HelloHealer|r showing fake debuff icon for 5s")
    elseif msg == "testlayout" or msg:match("^testlayout%s") then
        -- /hh testlayout [groupCount] [tankCount]
        -- Spawns a non-secure visual mock of the frame layout. Useful
        -- for sanity-checking sizing/overflow without needing 39 friends
        -- in a raid. Defaults to 40-man + 8 tanks.
        local g, t = msg:match("^testlayout%s+(%d+)%s+(%d+)$")
        if not g then g = msg:match("^testlayout%s+(%d+)$") end
        if ns.TestLayout and ns.TestLayout.Toggle then
            ns.TestLayout:Toggle(g, t)
        end
    elseif msg == "debug" then
        local cols = ns.Header and ns.Header.columns
        if not cols then
            print("|cff80ff80HelloHealer|r no header")
            return
        end
        for c = 1, #cols do
            local kids = { cols[c]:GetChildren() }
            print(("|cff80ff80HelloHealer|r column %d children: %d"):format(c, #kids))
            for i = 1, #kids do
                local u = kids[i]:GetAttribute("unit")
                print(("  [%d] unit=%s exists=%s"):format(i, tostring(u), tostring(u and UnitExists(u))))
            end
        end
    elseif msg == "tank" or msg:match("^tank%s+") then
        local name = raw:match("^[Tt][Aa][Nn][Kk]%s+(%S+)")
        if not name then
            if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") then
                name = ns.TankHeader.FullName("target")
            else
                print("|cff80ff80HelloHealer|r usage: /hh tank <name>  (or target a friendly player and use /hh tank)")
                return
            end
        else
            name = ns.TankHeader:ResolveName(name)
        end
        local list = HelloHealerCharDB.tankList
        for i = 1, #list do
            if list[i]:lower() == name:lower() then
                print("|cff80ff80HelloHealer|r already in tank list: " .. list[i])
                return
            end
        end
        table.insert(list, name)
        if ns.TankHeader and ns.TankHeader.RefreshNameList then ns.TankHeader:RefreshNameList() end
        print("|cff80ff80HelloHealer|r added tank: " .. name)
    elseif msg == "untank" or msg:match("^untank%s+") then
        local name = raw:match("^[Uu][Nn][Tt][Aa][Nn][Kk]%s+(%S+)")
        if not name then
            if UnitExists("target") and UnitIsPlayer("target") then
                name = ns.TankHeader.FullName("target")
            else
                print("|cff80ff80HelloHealer|r usage: /hh untank <name>  (or target a player and use /hh untank)")
                return
            end
        end
        local list = HelloHealerCharDB.tankList
        local removed
        for i = #list, 1, -1 do
            if list[i]:lower() == name:lower() then
                removed = table.remove(list, i)
                break
            end
        end
        if removed then
            if ns.TankHeader and ns.TankHeader.RefreshNameList then ns.TankHeader:RefreshNameList() end
            print("|cff80ff80HelloHealer|r removed tank: " .. removed)
        else
            print("|cff80ff80HelloHealer|r not in tank list: " .. name)
        end
    elseif msg == "scanui" then
        local count = 0
        for k, v in pairs(_G) do
            if type(v) == "table" and type(k) == "string"
               and type(v.GetObjectType) == "function"
               and (k:match("^DF") or k:match("^Dragonflight")
                    or k:match("^Compact") or k:match("^Party")) then
                local ok, shown = pcall(v.IsShown, v)
                if ok and shown then
                    print(("|cff80ff80HelloHealer|r %s"):format(k))
                    count = count + 1
                end
            end
        end
        print(("|cff80ff80HelloHealer|r %d candidate frames currently visible"):format(count))
    elseif msg == "scanleft" then
        -- List every globally-named visible frame in the upper-left
        -- quadrant of the screen, regardless of name prefix. Use this
        -- when scanui misses something. Some _G entries are mixin tables
        -- with method-shaped fields but no frame backing, so we gate via
        -- GetObjectType + pcall.
        local screenH = UIParent:GetHeight()
        local count = 0
        for k, v in pairs(_G) do
            if type(v) == "table" and type(k) == "string"
               and type(v.GetObjectType) == "function" then
                local ok, objType = pcall(v.GetObjectType, v)
                if ok and objType then
                    local shownOK, shown = pcall(v.IsShown, v)
                    if shownOK and shown then
                        local lOK, left = pcall(v.GetLeft, v)
                        local tOK, top  = pcall(v.GetTop, v)
                        local wOK, w    = pcall(v.GetWidth, v)
                        local hOK, h    = pcall(v.GetHeight, v)
                        if lOK and tOK and wOK and hOK
                           and left and top and w and h
                           and left < 500 and top > screenH / 2
                           and w > 30 and h > 15 then
                            print(("|cff80ff80HelloHealer|r %s @(%d,%d) %dx%d [%s]"):format(k, left, top, w, h, objType))
                            count = count + 1
                        end
                    end
                end
            end
        end
        print(("|cff80ff80HelloHealer|r %d visible frames in upper-left"):format(count))
    elseif msg == "config" or msg == "options" or msg == "settings" then
        if ns.Settings and ns.Settings.Open then ns.Settings:Open() end
    elseif msg == "resetbindings" then
        HelloHealerCharDB.bindings = {}
        ns.ClickCast:ApplyAll()
        print("|cff80ff80HelloHealer|r bindings reset to defaults")
    elseif msg == "bindings" then
        local list = ns.Bindings:Get()
        if #list == 0 then
            print("|cff80ff80HelloHealer|r no bindings")
        else
            print("|cff80ff80HelloHealer|r bindings for " .. tostring(ns.playerClass) .. ":")
            local btnNames = { "left", "right", "middle", "mouse4", "mouse5" }
            for _, b in ipairs(list) do
                local mod = (b.mod ~= "" and (b.mod .. "-")) or ""
                print(("  %s%s -> %s"):format(mod, btnNames[b.btn] or ("btn"..b.btn), b.spell))
            end
        end
    elseif msg:match("^bind%s+") or msg:match("^unbind%s+") or msg == "unbind" then
        -- /hh bind <combo> <spell>      e.g. "left", "shift-left", "ctrl-right"
        -- /hh unbind <combo>
        local isUnbind = msg:match("^unbind")
        local rest = raw:gsub("^[Bb][Ii][Nn][Dd]%s+", ""):gsub("^[Uu][Nn][Bb][Ii][Nn][Dd]%s+", "")
        local combo, spell
        if isUnbind then
            combo = rest:match("^(%S+)") or ""
        else
            combo, spell = rest:match("^(%S+)%s+(.+)$")
            if not combo or not spell then
                print("|cff80ff80HelloHealer|r usage: /hh bind <combo> <spell>  e.g. /hh bind shift-left Greater Heal")
                return
            end
        end
        -- Parse combo: zero or more "<mod>-" prefixes then a button name.
        -- Modifiers may be combined (e.g., "ctrl-shift-left"). Stored in
        -- canonical alt-ctrl-shift order.
        local BTN = { left = 1, right = 2, middle = 3, mouse4 = 4, mouse5 = 5,
                      ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5 }
        local parts = {}
        for tok in combo:gmatch("[^%-]+") do table.insert(parts, tok:lower()) end
        if #parts == 0 then
            print("|cff80ff80HelloHealer|r empty combo")
            return
        end
        local btnName = parts[#parts]
        local btn = BTN[btnName]
        if not btn then
            print("|cff80ff80HelloHealer|r unknown button: " .. btnName .. "  (left, right, middle, mouse4, mouse5)")
            return
        end
        local has = {}
        for i = 1, #parts - 1 do
            local m = parts[i]
            if m == "alt" or m == "ctrl" or m == "shift" then
                has[m] = true
            else
                print("|cff80ff80HelloHealer|r unknown modifier: " .. m .. "  (shift, ctrl, alt)")
                return
            end
        end
        local modParts = {}
        if has.alt   then table.insert(modParts, "alt")   end
        if has.ctrl  then table.insert(modParts, "ctrl")  end
        if has.shift then table.insert(modParts, "shift") end
        local mod = table.concat(modParts, "-")
        if isUnbind then
            ns.Bindings:Unset(btn, mod)
            print(("|cff80ff80HelloHealer|r unbound %s%s"):format(mod ~= "" and (mod .. "-") or "", btnName))
        else
            if not GetSpellInfo(spell) then
                print(("|cff80ff80HelloHealer|r unknown spell: %q (binding not saved)"):format(spell))
                return
            end
            ns.Bindings:Set(btn, mod, spell)
            print(("|cff80ff80HelloHealer|r bound %s%s -> %s"):format(mod ~= "" and (mod .. "-") or "", btnName, spell))
        end
        ns.ClickCast:ApplyAll()
    elseif msg == "tanks" then
        local list = HelloHealerCharDB.tankList
        if #list == 0 then
            print("|cff80ff80HelloHealer|r manual tank list: (empty)")
        else
            print("|cff80ff80HelloHealer|r manual tanks: " .. table.concat(list, ", "))
        end
    else
        print("|cff80ff80HelloHealer|r commands: /hh lock, /hh resetpos, /hh reset, /hh tank [name], /hh untank [name], /hh tanks, /hh config, /hh bind <combo> <spell>, /hh unbind <combo>, /hh bindings, /hh resetbindings, /hh testdebuff, /hh scandebuffs, /hh scanbuffs [unit], /hh testlayout [group] [tanks], /hh debug")
    end
end
