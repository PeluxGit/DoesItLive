local _, ns = ...

-- Saved settings and their defaults. Logic files only read ns.db; the options window writes it.
-- Look keys mirror DoesItDie's marker settings so its presets and styles carry over.
ns.DEFAULTS = {
    enabled = true,
    nameplates = true,         -- also on friendly nameplates (Blizzard's and nameplate addons')

    -- Block
    fillTexture = "flat",      -- see ns.FILL_STYLES
    fillColor = "green",       -- see ns.COLOR_PRESETS
    fillOpacity = 55,
    hotColors = "single",      -- single | spell | each
    segmentDividers = true,
    drain = "ticks",           -- ticks: steps down as each tick lands; smooth: shrinks continuously

    -- Outline and effects
    outlineStyle = "none",     -- dashed | solid | none
    dashLength = 4,
    outlineThickness = 1,
    outlineColor = "green",
    outlineOpacity = 100,
    pulseOutline = false,
    showGlow = false,
    glowSize = 4,
    showSpark = false,         -- flare on the block's end as each tick lands
    flashOnApply = false,      -- flash the block when you cast a HoT

    -- Text
    showLabel = false,
    labelPosition = "right",   -- right | center
    labelSize = 9,
    labelColor = "white",

    -- Accuracy
    afterIncoming = true,      -- start after the game's incoming heals (where EUI's green bar ends)
    scale = 100,               -- % multiplier on every estimate
    useBonusHealing = true,    -- tooltip + (+healing x coefficient) until the meter has taught a size
    learnFromMeter = true,     -- after each fight, learn real tick sizes from the damage meter
    learned = {},              -- [spellID] = { tick = average healing per tick, weight = ticks seen }

    debug = false,
}

-- Presets only set appearance (as in DoesItDie).
ns.PRESETS = {
    { id = "minimal", label = "Minimal", values = {
        fillTexture = "flat", fillColor = "green", fillOpacity = 55, hotColors = "single",
        outlineStyle = "none", pulseOutline = false, showGlow = false, showSpark = false,
        flashOnApply = false, showLabel = false, drain = "ticks",
    } },
    { id = "classic", label = "Classic", values = {
        fillTexture = "smooth", fillColor = "green", fillOpacity = 60, hotColors = "single",
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "gold", outlineOpacity = 100,
        pulseOutline = false, showGlow = false, showSpark = true, flashOnApply = true, showLabel = false,
        drain = "ticks",
    } },
    { id = "juicy", label = "Juicy", values = {
        fillTexture = "stripes", fillColor = "green", fillOpacity = 100, hotColors = "spell", segmentDividers = true,
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "green", outlineOpacity = 85,
        pulseOutline = true, showGlow = true, glowSize = 4, showSpark = true, flashOnApply = true,
        showLabel = false, drain = "smooth",
    } },
    { id = "debug", label = "Debug", values = {
        fillTexture = "flat", fillOpacity = 60, hotColors = "spell", segmentDividers = true,
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "white", outlineOpacity = 100,
        pulseOutline = false, showGlow = false, showSpark = false, flashOnApply = true,
        showLabel = true, labelPosition = "right", labelSize = 9, labelColor = "white", drain = "ticks",
    } },
}

ns.COLOR_PRESETS = {
    { id = "green",  label = "Green",  rgb = { 0.25, 0.9, 0.45 } },
    { id = "teal",   label = "Teal",   rgb = { 0.2, 0.85, 0.75 } },
    { id = "lime",   label = "Lime",   rgb = { 0.7, 1, 0.3 } },
    { id = "cyan",   label = "Cyan",   rgb = { 0.2, 0.9, 1 } },
    { id = "gold",   label = "Gold",   rgb = { 1, 0.85, 0.1 } },
    { id = "white",  label = "White",  rgb = { 1, 1, 1 } },
    { id = "purple", label = "Purple", rgb = { 0.7, 0.3, 1 } },
    { id = "pink",   label = "Pink",   rgb = { 1, 0.45, 0.6 } },
    { id = "black",  label = "Black",  rgb = { 0, 0, 0 } },
}

ns.FILL_STYLES = {
    { id = "flat",     label = "Flat" },
    { id = "smooth",   label = "Health bar texture" },
    { id = "raid",     label = "Raid bar texture" },
    { id = "stripes",  label = "Diagonal stripes" },
    { id = "gradient", label = "Fade in from left" },
    { id = "none",     label = "None (outline only)" },
}

ns.HOT_COLOR_MODES = {
    { id = "single", label = "One color (fill color)" },
    { id = "spell",  label = "By spell" },
    { id = "each",   label = "Different color per HoT" },
}

ns.OUTLINE_STYLES = {
    { id = "dashed", label = "Dashed" },
    { id = "solid",  label = "Solid" },
    { id = "none",   label = "None" },
}

ns.DASH_LENGTHS = {
    { id = 1,  label = "Fine dots (1px)" },
    { id = 2,  label = "Dots (2px)" },
    { id = 4,  label = "Short dashes (4px)" },
    { id = 8,  label = "Dashes (8px)" },
    { id = 16, label = "Long dashes (16px)" },
}

ns.DRAIN_MODES = {
    { id = "ticks",  label = "Step down each tick" },
    { id = "smooth", label = "Shrink smoothly" },
}

ns.LABEL_POSITIONS = {
    { id = "right",  label = "Inside the bar, right end" },
    { id = "center", label = "Centered on the bar" },
}

-- Seconds between HoT ticks when a spell has no override below.
ns.DEFAULT_TICK = 3

-- Per-spell settings, keyed by English spell name (all ranks).
--   coef:   share of +healing the whole HoT gets, used until the damage meter teaches a real size. Guesses.
--   tick:   tick interval in seconds.
--   color:  "By spell" color.
--   shape:  first and last tick relative to the average, for HoTs that front-load (straight line between).
--   party:  lands on the target's whole party (subgroup in a raid).
ns.SPELLS = {
    ["Rejuvenation"] = { coef = 0.80, color = { 0.3, 1, 0.4 } },
    ["Regrowth"]     = { coef = 0.50, color = { 0.2, 0.85, 0.75 } },
    ["Wild Growth"]  = { coef = 0.40, tick = 1, party = true, shape = { 1.3, 0.7 }, color = { 0.75, 1, 0.3 } },
    ["Renew"]        = { coef = 1.00, color = { 1, 0.95, 0.6 } },
    ["Riptide"]      = { coef = 0.50, color = { 0.3, 0.6, 1 } },
}

-- "Different color per HoT": each spell keeps the palette color it got first this session.
ns.HOT_PALETTE = {
    { 0.3, 1, 0.45 }, { 0.3, 0.75, 1 }, { 1, 0.8, 0.2 }, { 0.85, 0.4, 1 }, { 1, 0.45, 0.75 },
}

ns.REFRESH = 0.05  -- redraw interval while any HoT is running, seconds
ns.RESCAN = 1.0    -- how often frame adapters look for unit buttons, seconds
