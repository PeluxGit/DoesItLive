# DoesItLive

See at a glance how much healing your HoTs still have to do.

DoesItLive adds a block to health bars, right after current health and incoming heals, showing the healing your own heal-over-time spells will still land on that player. When the block reaches the end of the bar, your HoTs will top them off; when it falls short, they need more. It's the healer's counterpart to [DoesItDie](https://github.com/swirllyman/DoesItDie), which does the same for damage over time.

Made for World of Warcraft: Forever.

## Spells

Rejuvenation and Regrowth, every rank. Wild Growth, Renew and Riptide.

## Where the block shows

- **EllesmereUI**: raid, party, player, target and focus frames; nameplates
- **Blizzard**: raid-style party and raid frames, the classic party frames, player, target and focus frames, and nameplates
- **BetterBlizzFrames** health bars (untested)
- **ElvUI** and other oUF-based layouts (untested)
- **Nameplate addons**: Platynator, Threat Plates, and most others (Plater, KUI, ...) found automatically (untested)

Blocks show on you, your group (untested), your target and focus, and friendly nameplates.

## Looks

The options window (`/dil`) has a live preview, so you can see each change as you make it. Four presets get you started:

- **Minimal**: a plain green block
- **Classic**: health-bar texture, gold dashed outline, a spark on each tick, a flash when you cast
- **Juicy**: striped, a color per spell, glowing pulsing outline
- **Debug**: a color per spell, outlined, with the amount written on the bar

You can also pick the fill style and color, show each HoT in its own color, add an outline, glow, spark or flash, show the amount as text, and choose whether the block steps down as each tick lands or shrinks smoothly.

## Commands

| Command | What it does |
| --- | --- |
| `/dil` | Open the options |
| `/dil toggle` | Turn the blocks on or off |
| `/dil test` | Show sample blocks on every frame it found |

## Accuracy and limitations

Crits are counted at their average. Turn off "Include average crits" to see only the healing you're sure of.

- Some changes to your healing during a fight may not be reflected.
- In combat, the block of a HoT that ended early may occasionally keep showing for a while.
- English game client only.
- Health bars that fill right to left aren't supported.
- Only your own HoTs are shown, not other healers'.
- The game doesn't let addons touch friendly nameplates inside instances, so no blocks there.

## Credits

MIT license (see `LICENSE`). Marker styles, textures, the options window layout and nameplate support are adapted from DoesItDie by Joe Greive (MIT, see `LICENSE-DoesItDie.txt`).
