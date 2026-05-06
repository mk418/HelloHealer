-- LibHealComm-4.0 in this folder is the HealBot Continued fork. It
-- references a HealBot-set global (HEALBOT_GAME_VERSION) at line ~2092 in
-- ZONE_CHANGED_NEW_AREA; if absent, the comparison `nil > 2` aborts the
-- handler. We don't run alongside HealBot, so we set the global here
-- ourselves before the lib loads. Versioning matches HealBot's scheme:
--   1 = Classic Era, 2 = TBC, 3 = Wrath, 4+ = retail.
if _G.HEALBOT_GAME_VERSION then return end

local proj = _G.WOW_PROJECT_ID
if proj == _G.WOW_PROJECT_CLASSIC then
    _G.HEALBOT_GAME_VERSION = 1
elseif proj == _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC then
    _G.HEALBOT_GAME_VERSION = 2
elseif proj == _G.WOW_PROJECT_WRATH_CLASSIC then
    _G.HEALBOT_GAME_VERSION = 3
else
    _G.HEALBOT_GAME_VERSION = 4
end
