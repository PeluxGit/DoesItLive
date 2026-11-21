local _, ns = ...

local issecret = issecretvalue or function() return false end
local function say(msg) print("|cff40d090DoesItLive|r " .. msg) end

local function describe(v)
    if v == nil then return "nil" end
    if issecret(v) then return "SECRET" end
    return tostring(v)
end

-- What Forever lets this addon read right now.
local function probe()
    ns.anyActive() -- drops expired HoTs first
    say(("probe, %s combat"):format(ns.inCombat() and "IN" or "out of"))
    say("UnitHealthMax(player): " .. describe(UnitHealthMax("player")))
    say("UnitGetIncomingHeals: " .. (UnitGetIncomingHeals and describe(UnitGetIncomingHeals("player")) or "missing"))
    if ns.inCombat() then
        say("own auras: not read in combat (it taints)")
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL|PLAYER")
        if not ok then
            say("own aura on player: ERROR " .. tostring(aura))
        else
            say(("own aura on player: %s"):format(aura and (describe(aura.name) .. " expires " ..
                describe(aura.expirationTime)) or "none"))
        end
    end
    local DM = C_DamageMeter
    local healType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.HealingDone
    say(("damage meter: %s, healing type %s"):format(type(DM) == "table" and "yes" or "missing", describe(healType)))
    say("bonus healing (cached out of combat): " .. tostring(ns.bonusHealing()))
    local counts = {}
    for _, o in pairs(ns.overlays) do counts[o.source] = (counts[o.source] or 0) + 1 end
    local parts = {}
    for source, n in pairs(counts) do parts[#parts + 1] = source .. "=" .. n end
    say("health bars found: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    for key, byName in pairs(ns.hots) do
        for name, hot in pairs(byName) do
            say(("tracking %s on %s: %.0f first tick, %.1fs left%s"):format(name, key, hot.amounts[1],
                hot.expires - GetTime(), hot.auraSeen and " (aura confirmed)" or ""))
        end
    end
end

local HELP = {
    "/dil - options window",
    "/dil toggle - turn the blocks on or off",
    "/dil test - sample blocks on every frame found",
    "/dil probe - what the game lets the addon read (run in and out of combat)",
    "/dil learned - tick sizes learned from the damage meter",
    "/dil forget - forget learned tick sizes",
    "/dil debug - toggle debug messages",
}

SLASH_DOESITLIVE1 = "/dil"
SLASH_DOESITLIVE2 = "/doesitlive"
SlashCmdList.DOESITLIVE = function(msg)
    local cmd = (msg or ""):match("^%s*(%S*)"):lower()
    local db = ns.db
    if cmd == "" then
        ns.openOptions()
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
        say(db.enabled and "on" or "off")
        ns.redraw()
    elseif cmd == "test" then
        ns.testMode = not ns.testMode
        ns.rescan()
        if ns.testMode then ns.startTicker() else ns.redraw() end
        say("test " .. (ns.testMode and "on" or "off"))
    elseif cmd == "probe" then
        probe()
    elseif cmd == "learned" then
        local any = false
        for spellID, l in pairs(db.learned) do
            any = true
            say(("%s (%d): %.1f per tick, tooltip %.1f, from %d ticks"):format(l.name or "?", spellID, l.tick or 0,
                l.desc or 0, math.floor((l.weight or 0) + 0.5)))
        end
        if not any then say("nothing learned yet") end
    elseif cmd == "forget" then
        ns.forgetLearned()
        say("learned tick sizes forgotten")
    elseif cmd == "debug" then
        db.debug = not db.debug
        say("debug " .. (db.debug and "on" or "off"))
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end
