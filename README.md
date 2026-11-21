# DoesItLive

A World of Warcraft: Forever addon that shows the healing your own HoTs still have to do, as a block on health bars, after current health and incoming heals. It's the HoT counterpart to [DoesItDie](https://github.com/swirllyman/DoesItDie), which does the same for DoTs.

## Features

- Tracks your Rejuvenation, Regrowth, Wild Growth, Renew and Riptide on group members, your target, focus and friendly nameplates.
- Learns real tick sizes after each fight from the damage meter (includes +healing and talents).
- DoesItDie's marker styles: fill textures, per-HoT colors, dashed or solid outline, glow, spark on each tick, flash on cast, healing-left text. Presets: Minimal, Classic, Juicy, Debug.
- Options window with a live preview (`/dil`).

## Supported frames

- EllesmereUI: raid, party, player, target, focus, nameplates
- Blizzard: compact party/raid frames, default party frames, player, target, focus, nameplates
- BetterBlizzFrames health bars
- ElvUI and other oUF layouts
- Nameplates: Platynator, Threat Plates, and an automatic search for others (Plater, KUI, ...)

## Commands

| Command | |
|---|---|
| `/dil` | Options window |
| `/dil toggle` | Turn the blocks on or off |
| `/dil test` | Sample blocks on every frame found |
| `/dil probe` | What the game lets the addon read (run in and out of combat) |
| `/dil learned` | Tick sizes learned from the damage meter |
| `/dil forget` | Forget learned tick sizes |
| `/dil debug` | Debug messages |

## How it works on Forever

Forever applies secret values to addons. Health, max health and incoming heals are secret, and reading auras in combat taints the addon. So:

- HoTs are tracked from your own cast events (`UNIT_SPELLCAST_SENT` names the target by full name, `UNIT_SPELLCAST_SUCCEEDED` gives the spell) and their tooltips.
- Auras are read out of combat only, to correct expiry times and catch dispels.
- The block is drawn with StatusBars fed the secret values, never doing math on them.

## Development

`tests/` has a smoke test that loads the addon against stubbed WoW APIs:

```
pip install lupa
python tests/smoke.py
```

## Credits

Licensed under MIT (see `LICENSE`). Marker styles, textures, options window layout, nameplate support and damage meter learning are adapted from DoesItDie by Joe Greive (MIT, see `LICENSE-DoesItDie.txt`).
