# HelloHealer

A lean, opinionated healing UI for WoW Classic Era — Priest, Druid and Paladin only. Built around Blizzard's `SecureGroupHeaderTemplate` for reliability across patches.

> **Heads up** — this is a personal work in progress. I build and evolve it as I heal using it, so features land when I need them, design choices reflect my play style, and things may change between releases. Feel free to give it a whirl and leave me some feedback, but don't expect changes that fit your play style if it doesn't fit mine.

## Caveats

- No Shaman support as I don't play one at the moment (this might change in the future, but don't expect it anytime soon).
- This addon doesn't do anything for non-supported classes.
- Only works on Classic Era, no support for other game versions.
- Default click-cast bindings target max-level (60) characters — specific spell ranks like *Heal(Rank 3)* and *Renew(Rank 6)* are baked into the defaults. Lower-level characters will want to rebind via the settings panel or `/hh bind`.
- No auto-target / smart heal. You pick the target; the addon makes the click fast.
- Opinionated defaults. One settings panel, no twelve-tab profile editor — most things aren't user-tunable on purpose.
- DragonflightUI compatibility: auto-detects and skips party-frame suppression so it doesn't fight DragonflightUI's replacement frames.

## License

Released under the [MIT License](LICENSE).
