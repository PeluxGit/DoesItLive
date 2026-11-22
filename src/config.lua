local _, ns = ...

ns.DEFAULTS = {
    enabled = true,
    nameplates = true,

    -- Block
    fillTexture = "flat",      -- see ns.FILL_STYLES
    fillColor = "green",       -- see ns.COLOR_PRESETS
    fillOpacity = 55,
    hotColors = "single",      -- single | spell | each
    segmentDividers = true,
    drain = "ticks",           -- ticks | smooth

    -- Outline and effects
    outlineStyle = "none",     -- dashed | solid | none
    dashLength = 4,
    outlineThickness = 1,
    outlineColor = "green",
    outlineOpacity = 100,
    pulseOutline = false,
    showGlow = false,
    glowSize = 4,
    showSpark = false,
    flashOnApply = false,

    -- Text
    showLabel = false,
    labelPosition = "right",   -- right | center
    labelSize = 9,
    labelColor = "white",

    -- Accuracy
    afterIncoming = true,      -- start where the game's incoming heals end
    scale = 100,               -- % multiplier on every estimate
    includeCrits = true,

    debug = false,
}

-- Presets only set appearance.
ns.PRESETS = {
    { id = "minimal", label = "Minimal", values = {
        fillTexture = "flat", fillColor = "green", fillOpacity = 55, hotColors = "single",
        outlineStyle = "none", pulseOutline = false, showGlow = false, showSpark = false,
        flashOnApply = false, showLabel = false,
    } },
    { id = "classic", label = "Classic", values = {
        fillTexture = "smooth", fillColor = "green", fillOpacity = 60, hotColors = "single",
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "gold", outlineOpacity = 100,
        pulseOutline = false, showGlow = false, showSpark = true, flashOnApply = true, showLabel = false,
    } },
    { id = "juicy", label = "Juicy", values = {
        fillTexture = "stripes", fillColor = "green", fillOpacity = 100, hotColors = "spell", segmentDividers = true,
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "green", outlineOpacity = 85,
        pulseOutline = true, showGlow = true, glowSize = 4, showSpark = true, flashOnApply = true,
        showLabel = false,
    } },
    { id = "debug", label = "Debug", values = {
        fillTexture = "flat", fillOpacity = 60, hotColors = "spell", segmentDividers = true,
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "white", outlineOpacity = 100,
        pulseOutline = false, showGlow = false, showSpark = false, flashOnApply = true,
        showLabel = true, labelPosition = "right", labelSize = 9, labelColor = "white",
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

ns.CRIT_MULTIPLIER = 1.5

-- Spell schools, as GetSpellCritChance numbers them.
ns.SCHOOL_HOLY, ns.SCHOOL_NATURE = 2, 4

-- Per-spell settings, keyed by English spell name (all ranks).
--   tick:   tick interval in seconds.
--   color:  "By spell" color.
--   shape:  first and last tick relative to the average, for HoTs that front-load (straight line between).
--   party:  lands on the target's whole party (subgroup in a raid).
--   school: whose crit chance applies (a spell without one uses the highest of all schools).
ns.SPELLS = {
    ["Rejuvenation"] = { school = ns.SCHOOL_NATURE, color = { 0.3, 1, 0.4 } },
    ["Regrowth"]     = { school = ns.SCHOOL_NATURE, color = { 0.2, 0.85, 0.75 } },
    ["Wild Growth"]  = { school = ns.SCHOOL_NATURE, tick = 1, party = true, shape = { 1.3, 0.7 }, color = { 0.75, 1, 0.3 } },
    ["Renew"]        = { school = ns.SCHOOL_HOLY, color = { 1, 0.95, 0.6 } },
    ["Riptide"]      = { school = ns.SCHOOL_NATURE, color = { 0.3, 0.6, 1 } },
}

-- "Different color per HoT": each spell keeps the palette color it got first this session.
ns.HOT_PALETTE = {
    { 0.3, 1, 0.45 }, { 0.3, 0.75, 1 }, { 1, 0.8, 0.2 }, { 0.85, 0.4, 1 }, { 1, 0.45, 0.75 },
}

-- Redraw interval while any HoT is running, seconds.
ns.REFRESH_TICKS = 0.1
ns.REFRESH_SMOOTH = 0.05
ns.RESCAN = 5.0      -- seconds between periodic looks for new unit buttons
ns.AURA_RESCAN = 0.5 -- out of combat, seconds between aura reads per unit

-- Tick matching, seconds.
ns.TICK_WINDOW = 0.4       -- a heal this close to a HoT's due tick counts as that tick
ns.TICK_SYNC_WINDOW = 0.2  -- a match this close moves the HoT's timing onto the real tick
ns.TICK_MISS_AFTER = 0.6   -- no heal this long after a due tick: the HoT is gone (once one of its ticks was seen)
