local ADDON_NAME, ns = ...

ns.Config = {}
local Config = ns.Config

local accountDefaults = {
    layout = { size = "Normal", scale = 1.0 },
    autoIncludeMT = true,
    classDispelPriority = {
        PRIEST  = { "Magic", "Disease" },
        DRUID   = { "Curse", "Poison" },
        PALADIN = { "Magic", "Poison", "Disease" },
        SHAMAN  = { "Poison", "Disease" },
    },
    combatResModifier = "shift",
}

local charDefaults = {
    position = { point = "TOPLEFT", x = 15, y = -140 },
    locked = true,
    tankList = {},
    tankFramesEnabled = true,
    showPets = false,
    bindings = {},
    focusList = {},
    triageEnabled = true,
    framesHidden = false,
}

Config.defaultPosition = { point = "TOPLEFT", x = 15, y = -140 }

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

function Config:Init()
    HelloHealerDB = HelloHealerDB or {}
    HelloHealerCharDB = HelloHealerCharDB or {}
    applyDefaults(HelloHealerDB, accountDefaults)
    applyDefaults(HelloHealerCharDB, charDefaults)
end
