local ADDON_NAME, ns = ...

ns.BlizzardFrames = {}
local BF = ns.BlizzardFrames

-- Suppress by hooking the frame's OnShow to immediately hide it. This
-- avoids the SetParent-to-hidden-frame approach that previously tainted
-- DragonflightUI's secure BuffFrame: SetParent propagates protection /
-- taint into anything DragonflightUI hooks, while a non-secure OnShow
-- hook only takes effect when the frame tries to display.
--
-- Combat caveat: :Hide() on a protected frame is blocked in combat
-- lockdown. We fall back to alpha=0, which is a non-secure render
-- attribute that DOES work under lockdown — Blizzard / DragonflightUI
-- raid frames can re-show themselves on GROUP_ROSTER_UPDATE etc. during
-- combat, and without this fallback they'd flicker into view under our
-- cells until PLAYER_REGEN_ENABLED.
--
-- Why the alpha needs to be applied recursively to children + regions:
-- some Blizzard sub-elements (backdrops, title bars, the raid-manager
-- toggle handle) call SetIgnoreParentAlpha(true) so they keep rendering
-- even when their parent fades. Setting alpha=0 just on the parent left
-- those bits visible — the "holder behind the frames" the addon was
-- still letting through. Walking the whole tree forces every region to
-- be invisible regardless of its ignoreParentAlpha setting.
local function setAlphaDeep(frame, alpha)
    if not frame then return end
    if frame.SetAlpha then frame:SetAlpha(alpha) end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do setAlphaDeep(children[i], alpha) end
    end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r.SetAlpha then r:SetAlpha(alpha) end
        end
    end
end

local function safeHide(frame)
    if not frame then return end
    if InCombatLockdown() then
        setAlphaDeep(frame, 0)
        return
    end
    frame:Hide()
end

local function suppress(frame)
    if not frame then return end
    safeHide(frame)
    if not frame.__hh_suppressed then
        frame.__hh_suppressed = true
        frame:HookScript("OnShow", safeHide)
    end
end

local function isLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    elseif IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

local CONFLICTING_UIS = { "DragonflightUI", "ElvUI" }

function BF:Hide()
    suppress(CompactRaidFrameContainer)
    suppress(CompactRaidFrameManager)
    -- Toggle that Blizzard reparents to UIParent when the raid manager
    -- is "hidden" so the user can re-open it. Reparenting bypasses our
    -- parent-hide cascade, so we suppress it directly.
    suppress(CompactRaidFrameManagerDisplayFrameHiddenModeToggle)
    suppress(CompactRaidFrameManagerDisplayFrameHiddenModeToggleTopRight)
    suppress(CompactUnitFrameProfilesSaveButton)
    suppress(CompactUnitFrameProfiles)
    suppress(PartyFrame)
    suppress(CompactPartyFrame)
    for i = 1, MAX_PARTY_MEMBERS or 4 do
        suppress(_G["PartyMemberFrame" .. i])
    end
end

function BF:DetectedConflict()
    for _, name in ipairs(CONFLICTING_UIS) do
        if isLoaded(name) then return name end
    end
    return nil
end

-- Catch frames that re-showed during combat (when our :Hide() was
-- blocked), or that Blizzard re-shows on roster changes, OR that
-- didn't exist at PLAYER_LOGIN and have since been lazy-loaded
-- (CompactRaidFrameContainer is a notable example: it's created on
-- first raid join, well after our login-time suppress() runs).
-- suppress() is idempotent via the __hh_suppressed flag, so calling it
-- repeatedly only attaches the hook the first time the frame exists.
local function rehide()
    suppress(CompactRaidFrameContainer)
    suppress(CompactRaidFrameManager)
    suppress(CompactRaidFrameManagerDisplayFrameHiddenModeToggle)
    suppress(CompactRaidFrameManagerDisplayFrameHiddenModeToggleTopRight)
    suppress(CompactUnitFrameProfilesSaveButton)
    suppress(CompactUnitFrameProfiles)
    suppress(PartyFrame)
    suppress(CompactPartyFrame)
    for i = 1, MAX_PARTY_MEMBERS or 4 do
        suppress(_G["PartyMemberFrame" .. i])
    end
end

ns:On("PLAYER_REGEN_DISABLED", rehide)
ns:On("PLAYER_REGEN_ENABLED",  rehide)
ns:On("GROUP_ROSTER_UPDATE",   rehide)
ns:On("PLAYER_ENTERING_WORLD", rehide)
