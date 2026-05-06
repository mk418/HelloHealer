# HelloHealer — Design Document

A lean, opinionated healing addon for World of Warcraft Classic Era, intended to replace HealBot Continued for users who play Priest, Druid, or Paladin and want something that works out of the box and stays working across patches.

---

## Design philosophy

1. **Zero-config first launch.** Detect class + group context, apply sensible defaults, ready to heal. A settings panel exists but is one screen, not twelve.
2. **Reliability over features.** Lean on Blizzard's secure templates and standard events. No clever in-combat reconfiguration. Fewer moving parts = fewer breakages on patch days.
3. **You decide the target; the addon makes it fast.** No auto-target "smart heal" — those are exactly what break and feel wrong.

---

## Layout

```
              ┌────────┬────────┐
              │ Target │  ToT   │
              └────────┴────────┘
┌────────┐    ┌────────┬────────┬────────┬────────┐
│ Tank 1 │    │ G1.1   │ G3.1   │ G5.1   │ G7.1   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 2 │    │ G1.2   │ G3.2   │ G5.2   │ G7.2   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 3 │    │ G1.3   │ G3.3   │ G5.3   │ G7.3   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 4 │    │ G1.4   │ G3.4   │ G5.4   │ G7.4   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 5 │    │ G1.5   │ G3.5   │ G5.5   │ G7.5   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 6 │    │ G2.1   │ G4.1   │ G6.1   │ G8.1   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 7 │    │ G2.2   │ G4.2   │ G6.2   │ G8.2   │
├────────┤    ├────────┼────────┼────────┼────────┤
│ Tank 8 │    │ ...    │ ...    │ ...    │ ...    │
└────────┘    └────────┴────────┴────────┴────────┘
```

- **Group frames:** 1×N for 5-man, 4 columns × 10 rows for a 40-man raid (two parties per column: 1+2, 3+4, 5+6, 7+8). Each column is a separate `SecureGroupHeaderTemplate` with `groupFilter` and `groupingOrder` set to its two subgroups (e.g., column 2 uses `"3,4"` for both) and `groupBy = "GROUP"`, so the top half of the column is the lower subgroup and the bottom half is the higher subgroup, deterministically regardless of raid join order.
- **Target / Target-of-Target frames:** anchored above the group frames, left-aligned with the first group column. Two cells side by side.
- **Tank frames:** anchored to the left of the group frames, single column up to 10 tall (matches the group block's height), same cell size as group frames. Toggleable.
- **Always visible**, even out of combat / when solo.
- The whole block moves as one unit when repositioned.

### Behavior with Blizzard frames

- `CompactRaidFrameContainer`, `CompactRaidFrameManager`, `PartyMemberFrame1..4` are hidden and re-show is suppressed. Automatic, no toggle.
- Blizzard's `PlayerFrame`, `TargetFrame`, `TargetFrameToT` are **not** touched — they show castbars, level/elite status, and enemy buffs/debuffs that the heal cell deliberately omits.
- Cleanly restored on `/hh disable` or addon disable.

---

## Per-cell anatomy

```
┌─────────────────────────┐
│ Name              [DBF] │  ← name + dispellable debuff icon (if any)
│ ████████████░░░░░  82%  │  ← HP bar + missing-HP text, class-color tinted
│ ▓▓▓▓░░░░░░░░░░░░░       │  ← power bar (mana/rage/energy/focus)
│ [CD][CD]          [agg] │  ← cooldown row (mouseover only) + aggro indicator
└─────────────────────────┘
```

| Element | Behavior |
|---|---|
| Name | Truncated to fit |
| HP bar | Class-color tinted; missing-HP text shown when not full |
| Power bar | Shown for all units (mana/rage/energy/focus) |
| Dispellable debuff icon | Corner overlay; **only** debuffs your class can dispel; clicking with the dispel binding cures it |
| Aggro highlight | See "Threat highlighting" |
| Incoming heal indicator | LibHealComm-driven overlay |
| Range fade | Out of 40yd → dimmed (not hidden — hiding causes layout shifts) |
| Cooldown icons | Shown only on cell mouseover; small dimmed icons for your key heal CDs |
| Per-target restrictions | Always shown when active: Weakened Soul (Priest), Forbearance (Paladin), pending Rebirth (Druid — clears on accept/decline/timeout) |

---

## Click-cast bindings (per class)

Same scheme everywhere; only the spells differ.

| Click | Priest | Druid | Paladin |
|---|---|---|---|
| Left | Flash Heal | Healing Touch | Holy Light |
| Shift-Left | Greater Heal | Healing Touch | Holy Light |
| Right | Renew | Rejuvenation | Flash of Light |
| Shift-Right | Power Word: Shield | Regrowth | Flash of Light |
| Middle | Dispel Magic | Remove Curse | Cleanse |
| Shift-Middle | Resurrection | Rebirth (in combat) | Redemption |
| Mouse4 / Mouse5 | reserved for user | | |

**Combat-res safety:** clicking the res binding while in combat requires a modifier (default `shift`) to avoid wasting Druid Rebirth.

**Mouseover macro compatibility:** `/cast [@mouseover]` macros work alongside click-cast — the secure header sets the mouseover attribute correctly.

### Click target on enemy frames

When the Target frame holds an enemy, left-click casts on **target-of-target** (the standard healer workflow — heal whoever the tank is hitting).

---

## Threat highlighting

Driven by `UnitThreatSituation(unit)` and `UNIT_THREAT_SITUATION_UPDATE`. Graduated borders with intentional asymmetry between non-tank and tank frames:

| Tier | Meaning | Non-tank cell | Tank cell |
|---|---|---|---|
| 0 | Below tank | none | **red border** (lost aggro entirely) |
| 1 | Higher threat, not yet hit | **yellow border** (about to pull) | **orange border** (lost the lead) |
| 2 | Higher threat, being hit | **orange border** (has aggro) | **yellow border** (lead slipping) |
| 3 | Tanking | **red border** (panic — heal NOW) | **purple border** (holding aggro) |

Same data, opposite framing per frame type — for non-tanks a rising tier is bad, for tanks a falling tier is bad. Tank tier 3 surfaces as purple so the healer can see at a glance which tank currently has the boss. Repaint capped at one per cell per frame to handle AoE-pull event spam.

---

## Dispel handling

Default priority order per class:

| Class | Priority |
|---|---|
| Priest | Magic > Disease |
| Druid | Curse > Poison |
| Paladin | Magic > Poison > Disease |
| Shaman | Poison > Disease |

The corner debuff icon shows only the highest-priority dispellable debuff. Clicking it with the dispel binding cures it. No separate Decursive-style addon needed.

---

## Roster sizes

There's no roster-size detection logic and no manual override. The
secure header's column-packing (`unitsPerColumn = 10`, `maxColumns = 4`)
collapses gracefully as the roster shrinks, producing the right shape
for every context out of the box:

| Context | Layout |
|---|---|
| Solo / out-of-group | Self cell + tanks (if configured) |
| 5-man | 1 column of 5 |
| 10-man | 1 column of 10 |
| Raid (20-man) | 2 columns of 10 |
| Raid (40-man) | 4 columns of 10 (two parties per column) |
| PvP / Arena | Same as PvE; **no enemy frames** |

---

## Tank frames

Sources for the tank list, in priority order:

1. Players assigned the **Main Tank** raid role (Blizzard's built-in)
2. Per-character saved tank list (`/hh tank add <name>`)

Auto-detection by stance/form/aura is **off** by default — too unreliable to trust.

Tank cells are the same size as group cells, anchored to the left. They surface tank-specific info: aggro state (per the threat table above), defensive cooldowns active (Shield Wall, Last Stand, Barkskin, Divine Shield).

Toggleable with `/hh tanks` or via the settings panel.

---

## Settings panel — one screen

```
┌─ HelloHealer ──────────────────────────────────────────┐
│                                                         │
│ LAYOUT                                                  │
│   Size:   ( ) Compact  (•) Normal  ( ) Large            │
│   Scale:  ─────●──────  100%                            │
│   [ ] Lock frame position    [ Reset position ]         │
│                                                         │
│ FRAMES                                                  │
│   [✓] Tank frames                                       │
│       Manual list:  Thargas  Brokk  [+ Add  − Remove]   │
│       [✓] Auto-include raid Main Tanks                  │
│   [✓] Target frame                                      │
│   [✓] Target-of-target frame                            │
│                                                         │
│ CLICK-CAST BINDINGS                          (per-class)│
│   Showing: (•) Priest  ( ) Druid  ( ) Paladin           │
│   ┌──────────────────┬────────────────────────┐         │
│   │ Left             │ Flash Heal             │ [Edit]  │
│   │ Shift-Left       │ Greater Heal           │ [Edit]  │
│   │ Right            │ Renew                  │ [Edit]  │
│   │ Shift-Right      │ Power Word: Shield     │ [Edit]  │
│   │ Middle           │ Dispel Magic           │ [Edit]  │
│   │ Shift-Middle     │ Resurrection           │ [Edit]  │
│   └──────────────────┴────────────────────────┘         │
│   Combat-res modifier: (•) Shift  ( ) Ctrl  ( ) Alt     │
│                                                         │
│ DISPEL PRIORITY                                         │
│   Magic ▲▼   Curse ▲▼   Poison ▲▼   Disease ▲▼          │
│                                                         │
│                          [ Reset to defaults ] [ Close ]│
└─────────────────────────────────────────────────────────┘
```

### Deliberately omitted

- Custom layouts editor
- Per-cell font / texture / color pickers — one opinionated style
- Per-element visibility toggles (HoTs, power bar, dispel icon, threat border, etc.) — uniform style is the design goal
- Profile system (auto-scoped storage replaces it)
- "Show in raid only" / "Hide in city" toggles
- Smart targeting / auto-heal lowest

### Slash commands

```
/hh                       open settings
/hh lock                  lock/unlock frame
/hh tanks                 toggle tank frames
/hh tank add <name>
/hh tank remove <name>
/hh bind <class> <click> <spell>
/hh reset                 wipe all settings to defaults
```

---

## Storage schema

Auto-scoped — no user-facing profile management.

```lua
HelloHealerDB = {                          -- account-wide
  layout = { size = "Normal", scale = 1.0 },
  autoIncludeMT = true,
  classBindings = {                         -- keyed by class token
    PRIEST  = { ... },
    DRUID   = { ... },
    PALADIN = { ... },
  },
  classDispelPriority = { PRIEST = {"Magic","Disease"}, ... },
  combatResModifier = "shift",
}

HelloHealerCharDB = {                      -- per-character
  position = { point="CENTER", x=0, y=-100 },
  locked = false,
  tankList = { "Thargas", "Brokk" },
  tankFramesEnabled = true,
}
```

| Scope | Why |
|---|---|
| Per-character | Frame position, lock state, tank list |
| Per-class (account-wide) | Click-cast bindings, dispel priority — same Priest plays the same way on any server |
| Account-wide | Visual preferences, cell content toggles |

This auto-scoping eliminates the need for a profile UI entirely.

---

## Technical foundation

### SecureGroupHeaderTemplate

The single most important technical decision. Don't roll your own roster management — use Blizzard's `SecureGroupHeaderTemplate`. It:

- Auto-spawns child buttons for each group member matching a filter
- Handles party↔raid transitions for you
- Survives reloads, mid-combat group joins, and zone changes without custom code
- Has a stable Blizzard-maintained API

Every reliable healer addon (Grid2, Vuhdo, ElvUI, Cell) uses it. HealBot's reinvention of this layer is exactly why it breaks on updates.

| Header | Filter | Purpose |
|---|---|---|
| `MainHeader` | All groups 1–8 | Group grid |
| `TankHeader` | nameList + MT role | Tank column |
| `TargetButton` | unit = "target" | Single secure button, not a header |
| `ToTButton` | unit = "targettarget" | Single secure button, not a header |

### File structure

```
HelloHealer/
├── HelloHealer.toc
├── Core.lua              -- namespace, slash commands, init order
├── Config.lua            -- saved-variables schema, defaults, settings panel
├── BlizzardFrames.lua    -- hide & suppress party/raid frames
├── Header.lua            -- create the SecureGroupHeaders + Target/ToT buttons
├── Cell.lua              -- the cell template (visual layers + secure setup)
├── ClickCast.lua         -- attribute management for click-cast bindings
├── Bindings.lua          -- per-class default binding tables, edit flow
├── Tanks.lua             -- tank list + MT role detection
├── Dispatcher.lua        -- single event dispatcher → module callbacks
├── Modules/
│   ├── Health.lua
│   ├── Power.lua
│   ├── Aura.lua          -- dispel debuff filtering & icon
│   ├── Threat.lua        -- graduated border highlight
│   ├── IncomingHeal.lua  -- LibHealComm consumer
│   ├── Range.lua         -- throttled OnUpdate, fade only
│   ├── Cooldown.lua      -- mouseover-only CD icons
│   └── Rebirth.lua       -- pending-res indicator
└── Libs/
    ├── LibStub/
    └── LibHealComm-4.0/
```

Each module is self-contained: registers its events with the Dispatcher, owns its visual layer on the cell, can be disabled by toggling its `enabled` flag. Removing a module file should not break anything else.

### Combat-safety strategy

The rule: **never touch protected attributes, parentage, or anchors during combat.**

| Operation | Combat-safe? |
|---|---|
| `SetAttribute` on cell | NO → queue |
| `SetPoint` / `SetParent` on cell | NO → queue |
| `Show` / `Hide` on cell | YES (header manages) |
| Update HP text / bar fill | YES |
| Add/remove non-secure overlay | YES |
| Register/unregister events | YES |

A `CombatQueue` collects deferred operations and flushes them on `PLAYER_REGEN_ENABLED`. The settings panel disables binding-edit controls during combat with a tooltip explaining why.

### Event dispatcher

Single `CreateFrame("Frame")` with one `OnEvent`. Modules register callbacks keyed by event name. Throttling rules baked in:

- `UNIT_AURA` → coalesced per unit, max one repaint per frame
- Range check → throttled `OnUpdate` at 0.2s, never an event
- Threat → repaint per cell capped at one per frame regardless of event volume

All events use `RegisterUnitEvent` where supported — cuts `UNIT_AURA` volume by ~10× in raids.

### Click-cast layer

Standard secure-attribute pattern, applied once at cell creation:

```lua
cell:SetAttribute("type1", "spell")
cell:SetAttribute("spell1", "Flash Heal")
cell:SetAttribute("shift-type1", "spell")
cell:SetAttribute("shift-spell1", "Greater Heal")
-- ...
```

The cell's `unit` attribute is set by the SecureGroupHeader — we never touch it. Editing a binding from the UI: validates the spell exists in the player's spellbook, applies immediately or queues for `PLAYER_REGEN_ENABLED`.

### Library distribution

Embedded via `.pkgmeta` at packaging time. LibStub guarantees only the highest version of any given library actually runs even if multiple addons embed it, so embedding is safer than depending on a separate standalone install (which can update independently and break us).

```yaml
# .pkgmeta
package-as: HelloHealer
externals:
  Libs/LibStub:
    url: https://repos.curseforge.com/wow/libstub/trunk
  Libs/LibHealComm-4.0:
    url: https://repos.curseforge.com/wow/libhealcomm-4-0/trunk
```

### Reliability practices

- **No frame-walking.** Never reach into Blizzard internals via `_G.SomeFrame.somechild`.
- **No mixin abuse.** Never monkey-patch Blizzard methods (HealBot does this for raid frames — it's the #1 patch-day breakage).
- **One library version pinned.** Library upgrades are reviewed, not automatic.
- **No taint surface.** The addon never modifies global tables. Everything lives under `HelloHealer.*`.
- **PTR smoke test before each Blizzard patch.** Five minutes catches 90% of breakages.

### Boot sequence

```
1. ADDON_LOADED       → load SavedVariables, apply defaults
2. (immediately)      → BlizzardFrames.Hide()
3. (immediately)      → Header.Create() ×2 + Target/ToT buttons
4. (immediately)      → Cell template applied to each header child
5. (immediately)      → ClickCast.ApplyBindings(class)
6. PLAYER_LOGIN       → first roster paint
7. (any time after)   → modules respond to events as they fire
```

---

## Install

```sh
ln -s /path/to/HelloHealer \
  ~/Applications/World\ of\ Warcraft/_classic_era_/Interface/AddOns/HelloHealer
```

Update the WoW path to your install. If the addon shows "Out of Date," check `/dump (select(4, GetBuildInfo()))` in-game and update the `## Interface:` line in the TOC.

---

## Implemented

### Foundation
- [x] Project skeleton + TOC
- [x] Event dispatcher (`Core.lua`)
- [x] SavedVariables defaults + auto-merge (`Config.lua`)
- [x] Conditional Blizzard frame suppression (`BlizzardFrames.lua`) — uses `SetParent` to hidden frame to avoid taint; auto-detects DragonflightUI / ElvUI and skips party-frame suppression when present
- [x] Loads only on Priest/Druid/Paladin

### Frames & layout
- [x] `SecureGroupHeaderTemplate` foundation with auto-skin (`Header.lua`)
- [x] Cell template with HP bar, name, missing-HP text, class-color tint (`Cell.lua`)
- [x] Drag-to-move handle with lock toggle, position persistence to `HelloHealerCharDB.position`
- [x] Default position: TOPLEFT, 15, -140 (matches Blizzard party-frame default)
- [x] Locked by default

### Click-cast
- [x] Per-class default bindings for Priest/Druid/Paladin (`Bindings.lua`)
- [x] Macrotext `[@mouseover]` approach — clean "Out of range" failure, no auto-self-cast, no pending cursor cast (`ClickCast.lua`)
- [x] Combat-queued attribute application

### Cell modules
- [x] **Health** (`Modules/Health.lua`) — HP bar updates on `UNIT_HEALTH` / `UNIT_MAXHEALTH`
- [x] **Power** (`Modules/Power.lua`) — power bar at the bottom of the cell, colored by power type (mana / rage / energy / focus)
- [x] **Range** (`Modules/Range.lua`) — 0.2s throttled fade for out-of-range cells, per-class 40yd heal spell (Flash Heal / Healing Touch / Holy Light / Healing Wave)
- [x] **Aura** (`Modules/Aura.lua`) — class-dispellable debuff icon in the top-right corner; supports both `C_UnitAuras.GetDebuffDataByIndex` and legacy `UnitDebuff`
- [x] **HoT** (`Modules/HoT.lua`) — heal-over-time icons on cells, player-cast only, name-keyed per healing class (Rejuvenation/Regrowth/Renew). Supports spellID overrides so set-bonus procs (e.g. Priest T2 8-piece Renew, spellID 22009) render with a distinguishing icon

### Slash commands
- [x] `/hh` and `/hellohealer` registered
- [x] `/hh lock`, `/hh resetpos`, `/hh reset`
- [x] `/hh suppress` — toggle party-frame suppression (in case auto-detection misses a UI replacement addon)
- [x] `/hh debug` — print header child count + per-child unit attribute
- [x] `/hh testdebuff` — fake debuff icon on player cell for 5s (visual layer test)
- [x] `/hh scandebuffs` — print all debuffs currently on player with type and icon
- [x] `/hh testlayout [group] [tanks]` — spawn a non-secure visual mock of the layout (defaults 40 + 8) to eyeball sizing/overflow without needing a real raid

---

## TODO

### Frames & layout

- [x] Tank header (left column, name list + MT role detection + manual `/hh tank` list)
- [x] Target frame (single secure button, anchored above group)
- [x] Target-of-target frame (paired with Target)
- [x] When Target is friendly and in the group/tank list, additionally highlight that player's existing cell with a subtle outer glow (`Modules/TargetGlow.lua`). Soft cyan additive ring just outside the cell, low alpha so it stays out of the threat-tier / aggro-highlight wells. The dedicated Target/ToT cells deliberately do not glow themselves — the highlight only surfaces the underlying group/tank cell.
- [x] Verify column anchor direction in raid layout (working in groups + raid)

### Cell modules

- [x] **Threat.lua** — graduated border, role-aware (TANK role / `/maintank` invert)
- [x] **IncomingHeal.lua** — LibHealComm-4.0 callbacks, green segment on HP bar
- [x] **CooldownTrack.lua** — bottom-left icons + cooldown swipe for class-tracked auras (Weakened Soul, Power Infusion, Innervate, Forbearance, BoP)
- [x] **PendingRes.lua** — pending-res indicator (Rebirth / Soulstone / normal Resurrection) via `UnitHasIncomingResurrection` + `INCOMING_RESURRECT_CHANGED`; clears automatically on accept/decline/timeout
- [x] **Defensives.lua** — active defensive-cooldown icons (Shield Wall / Last Stand / Shield Block / Barkskin / Frenzied Regen / Divine Shield / Divine Protection) on the bottom-right of tank cells, with cooldown swipe + countdown text. The same scan also feeds a "Defensives:" section in the cell tooltip with a live remaining-duration timer (visible on every cell, not just tanks)
- [x] **MissingBuffs.lua** — class-scoped raid-buff tracker (Priest: Fortitude + Spirit; Druid: Mark of the Wild; both versions of each spell satisfy the category). A 3 px solid amber bar outside the cell's left edge (lives in the column gap, or open space for column-1 / tank cells) signals any group/tank cell missing one of the player's class buffs, plus a "Missing buffs:" tooltip section listing what's missing. Left-edge bar chosen over an outer-ring glow because the 2 px row gap is too tight for adjacent rings to coexist without doubling up; chosen over an inner full-cell tint because that competed with the class-coloured HP fill. Skips Target/ToT cells, non-player units, and offline players. Spirit category is suppressed for warriors/rogues (no mana to regenerate); hunters still get the alert
- [x] **Focus.lua** — per-character focus list for raid healing assignments. Bright pink outer-ring glow (additive blend, same geometry as TargetGlow) on the existing group/tank cell of any name in `HelloHealerCharDB.focusList`. Managed via `/hh focus [name]` (add, or use targeted friendly), `/hh unfocus [name]`, `/hh focuses` (list), `/hh focus clear` (wipe). When the focused player is also your current target the cyan + pink glows additive-blend rather than fighting for pixels. Skips Target/ToT cells, non-player units. Persists across reloads for mid-raid recovery; auto-cleared on `GROUP_LEFT` (alongside the tank list)
- [x] **Triage.lua** — bright white outer-ring glow (additive, same geometry as TargetGlow / Focus) on cells whose predicted post-heals HP fraction `(currentHP + LibHealComm-predicted incoming heals * heal modifier) / maxHP` falls below 0.50. Naturally suppresses itself when other healers already have the gap covered. Pure white at high alpha so it dominates the additive stack — even when a triage cell is also your target/focus the white reads as the "heal NOW" signal. Skips Target/ToT cells, non-player units, dead/ghost players (PendingRes handles them), and offline players. Degrades to plain `currentHP/maxHP < 0.50` when LibHealComm isn't available. Per-character toggle (`HelloHealerCharDB.triageEnabled`, default on) via the settings panel checkbox or `/hh triage [on|off]` for quick mid-fight switching

### Click-cast

- [-] Combat-res modifier enforcement (Druid Rebirth requires shift in combat) — *deliberately skipped, user prefers explicit binding*
- [x] Spell validation against player's spellbook before applying a binding — `ClickCast.lua` skips bindings whose spell `GetSpellInfo` can't resolve, so unknown spells fail at apply time instead of at click time
- [x] Per-class binding editor — `/hh bind`, `/hh unbind`, `/hh bindings`, `/hh resetbindings`; settings panel hosts editable rows with Clear/Add UI
- [x] Mouse4 / Mouse5 user binding slots — usable via the binding editor

### Settings panel

- [x] One-screen Blizzard-options-integrated panel — `Settings.lua` registers via `Settings.RegisterCanvasLayoutCategory` with a legacy `InterfaceOptions_AddCategory` fallback
- [x] Tank list add/remove UI
- [x] Click-cast binding rows with Edit/Clear/Add UI
- [x] Combat-state awareness in the settings panel — every secure-touching control (scale slider, reset-position, use-default-bindings, all per-row Edit / Clear / Add / Remove buttons and their EditBoxes) is disabled in combat with a tooltip explaining why. Lock-frames checkbox and the "Reset everything (reload)" button stay enabled. State refreshes on `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` and on every panel `OnShow`.
- [x] Reset-to-defaults button — "Reset everything (reload)" wipes both saved-variables tables and reloads the UI

### Tanks

- [x] Manual tank list management (`/hh tank [name]`, `/hh untank [name]`, `/hh tanks`)
- [x] Auto-include raid Main Tanks (`/maintank` + `/mainassist` + role=TANK)
- [x] Tank header anchored to the left of the group block (auto-shifts main header right when populated). Single column, 10 tanks max — matches the group block's column height.
- [x] Defensive cooldown overlay — implemented in `Modules/Defensives.lua`; see Cell modules section above

### Dispel

- [x] Per-class default priority lists in defaults — used to order the (now multi-slot) top-right debuff icons stably; not user-configurable
- [x] Multiple dispellable debuff icons displayed in the top-right (2 slots, ordered by priority); 3rd school for Paladin overflows to tooltip's "Dispellable:" section
- [x] Corner debuff icon clickable with the dispel binding (works via existing middle-click binding)

### Reliability / packaging

- [x] `.pkgmeta` with externals for LibStub and LibHealComm-4.0
- [ ] CurseForge release workflow (BigWigs Packager GitHub Action) — deferred until ready to publish; `.github/workflows/release.yml` not yet created
- [x] Verify TOC `## Interface:` against current Classic Era patch (currently `11508`)
- [ ] PTR smoke-test checklist (load, group, click-cast, dispel, raid swap, reload-in-combat)
- [ ] Validate WoWAce LibHealComm-4.0 externals on Classic Era at first packaged build; if broken, switch to embedded libs (commit `Libs/`, drop the `externals:` block in `.pkgmeta`)

### Known design decisions deferred

- [ ] Pet frames (out of scope for v1; revisit if hunters/warlocks ask)
- [ ] Pre-spawn all 40 raid slots at addon load — current workaround (alpha-0 hide of our headers when joining a group during combat, plus the post-combat `skinAll` catch-up; see `Header.lua` `joinedInCombat` flag) is in place. Deferred until real-raid testing shows whether the workaround is sufficient or whether the cascading-taint scenario in *Known issues* surfaces often enough to justify the secure-environment work (`SecureHandlerSetFrameRef` + `SecureHandlerExecute`)

---

## Known issues

### Mid-combat roster changes can produce a `nil unitButton` error (and a cascading taint error)

When a player joins or leaves your group while you're in combat, `SecureGroupHeader_Update` tries to spawn a new child button — but creating new secure frames is restricted in combat. The header errors with `attempt to index local 'unitButton' (a nil value)` (Blizzard's code, in `SecureGroupHeaders.lua:208`). The frames recover correctly once combat ends.

**Cascading taint:** once the secure header fails in combat, the failure taints the secure framework. The next time `SecureAuraHeader_Update` runs (e.g., a buff/debuff change on the player), its `Frame:Hide()` call gets blocked and the error is attributed to HelloHealer. With DragonflightUI loaded, this is especially visible because DragonflightUI's `DFPlayerBuffHeader` is one of those secure aura headers. Disabling DragonflightUI removes the visible cascade but doesn't remove the root cause.

**Why we don't pre-spawn yet:** A naive pre-spawn (manually `CreateFrame` 40 buttons and assign them to `header[1..40]`) doesn't work — Blizzard's secure header doesn't recognize externally-created children as its own and creates its own buttons separately, leaving 40 unused buttons sitting around. The proper fix is to use `SecureHandlerSetFrameRef` + `SecureHandlerExecute` to invoke the spawn logic from inside the secure environment. Deferred until needed.

**Impact:** these errors are spam, not breakage. Frames continue rendering, click-cast continues working, healing continues working. The errors only fire during a transient state (mid-combat roster change). If BugSack/BugGrabber notifications are noisy, the errors can be muted at the logger level.

### `UNIT_AURA` may fire intermittently for some aura changes

We observed a case where a debuff applied to the player only registered visually after a separate event (shapeshift) re-fired `UNIT_AURA`. If this happens reliably, the right fix is to subscribe to `COMBAT_LOG_EVENT_UNFILTERED` and filter for `SPELL_AURA_APPLIED` / `SPELL_AURA_REMOVED` on relevant units — the combat log doesn't share state with the secure aura system, so it doesn't taint. We previously tried a 0.5s polling ticker calling `C_UnitAuras` and it caused taint propagation, so polling is the wrong approach.

### Calling `SecureGroupHeader_Update` from non-secure code triggers DragonflightUI's mask accumulation

The single biggest taint surface we hit was calling `SecureGroupHeader_Update(header)` directly from non-secure code. DragonflightUI's `Buff.mixin.lua` hooks into the secure aura header pipeline and adds a mask texture each time the function fires. Each non-secure call accumulates a mask on their player buff/debuff icons. Once a `BuffFrame` icon hits its 3-mask limit, all subsequent updates fail with `AddMaskTexture(): Texture already has the maximum number of mask textures (3)`, and HelloHealer is blamed for the cascade.

**Fix:** never call `SecureGroupHeader_Update` directly. To force the header to populate at addon load (after our attribute setup), use a `Hide()` + `Show()` toggle instead — the secure header's internal `OnShow` script triggers an update via a private path that DragonflightUI doesn't hook. After initial population, Blizzard's own internal event registrations handle subsequent updates.

### DragonflightUI's transparent buff icons (when above bug is triggered)

DragonflightUI's `Buff.mixin.lua` doesn't gracefully handle being re-invoked on the same icon — once the 3-mask limit is hit, the icon renders transparent. This is their bug (the error is explicitly tagged `Lua Taint: DragonflightUI`). HelloHealer's mitigation is the no-`SecureGroupHeader_Update` rule above. If their bug is fixed upstream, this becomes a non-issue.

### Reparenting `PartyMemberFrame1..4` taints DragonflightUI / ElvUI

`SetParent` on PartyMemberFrame to a hidden parent taints the frame's `SecureAuraHeader` children, which propagates to UI replacement addons that hook into the same aura subsystem. HelloHealer auto-detects these addons (DragonflightUI, ElvUI) and skips ALL Blizzard frame suppression when one is loaded — those addons replace the frames anyway. Use `/hh suppress` to manually toggle if your UI replacement isn't auto-detected. Use `/hh aura off` to disable the dispel-icon module manually if a future taint surface ever surfaces.
