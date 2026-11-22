local addonName, ns = ...

local issecret = issecretvalue or function() return false end
local function say(msg) print("|cff40d090DoesItLive|r " .. msg) end

local function describe(v)
    if v == nil then return "nil" end
    if issecret(v) then return "SECRET" end
    return tostring(v)
end

local function accessible(t)
    if t == nil or issecret(t) or type(t) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, allowed = pcall(canaccesstable, t)
    return ok and allowed == true
end

---------------------------------------------------------------------------
-- Probe listener: for a while after each probe, reports whether aura updates, heal events and the combat
-- log come through readable.
---------------------------------------------------------------------------

local WATCH_SECONDS = 60
local MAX_WATCH_LINES = 30
local MAX_PER_KIND = 3
local MAX_HEAL_LINES = 8 -- enough heals to see a HoT's tick rhythm

local watcher = CreateFrame("Frame")
local watchToken, watchLines, perKind, watchStart = 0, 0, {}, 0
local knownAuraIDs = {} -- [auraInstanceID] = "Rejuvenation on Daft Druid", from the last out-of-combat probe

local function stopWatch(reason)
    watcher:UnregisterAllEvents()
    watchToken = watchToken + 1
    say("probe listener stopped (" .. reason .. ")")
end

local function report(kind, msg, limit)
    if (perKind[kind] or 0) >= (limit or MAX_PER_KIND) then return end
    perKind[kind] = (perKind[kind] or 0) + 1
    watchLines = watchLines + 1
    say(("probe %s%s: %s"):format(ns.inCombat() and "[combat] " or "", kind, msg))
    if watchLines >= MAX_WATCH_LINES then stopWatch("line limit") end
end

local function groupToken(unit)
    return unit == "player" or unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil
end

local function onUnitAura(unit, info)
    if issecret(unit) then return report("UNIT_AURA", "unit token SECRET") end
    if type(unit) ~= "string" or not groupToken(unit) then return end
    if info == nil then return report("UNIT_AURA", unit .. ": no update info") end
    if not accessible(info) then return report("UNIT_AURA", unit .. ": update info SECRET or locked") end
    local ok, err = pcall(function()
        -- A secret isFullUpdate doesn't mean the id lists are secret too: keep looking.
        local full = info.isFullUpdate
        if issecret(full) then
            report("UNIT_AURA full", unit .. ": isFullUpdate SECRET")
        elseif full then
            return report("UNIT_AURA full", unit .. ": full update (no ids)")
        end
        local removed = info.removedAuraInstanceIDs
        if removed ~= nil then
            if not accessible(removed) then
                report("UNIT_AURA removed", unit .. ": removed ids SECRET or locked")
            elseif #removed > 0 then
                local ids = {}
                for i = 1, math.min(#removed, 4) do
                    local id = removed[i]
                    local known = not issecret(id) and knownAuraIDs[id]
                    ids[#ids + 1] = describe(id) .. (known and (" = your " .. known) or "")
                end
                report("UNIT_AURA removed", unit .. ": " .. table.concat(ids, ", "))
            end
        end
        local added = info.addedAuras
        if added ~= nil then
            if not accessible(added) then
                report("UNIT_AURA added", unit .. ": added auras SECRET or locked")
            elseif #added > 0 then
                local a = added[1]
                if not accessible(a) then
                    report("UNIT_AURA added", unit .. ": aura data SECRET or locked")
                else
                    report("UNIT_AURA added", ("%s: %s id %s from %s (%d added)"):format(unit, describe(a.name),
                        describe(a.auraInstanceID), describe(a.sourceUnit), #added))
                end
            end
        end
    end)
    if not ok then report("UNIT_AURA error", unit .. ": " .. tostring(err)) end
end

-- Times are seconds since the probe started, so a HoT's tick rhythm shows.
local function onUnitCombat(unit, action, flags, amount, school)
    if issecret(unit) then return report("UNIT_COMBAT", "unit token SECRET") end
    if type(unit) ~= "string" or not groupToken(unit) then return end
    local kind = "UNIT_COMBAT " .. (issecret(action) and "SECRET action" or tostring(action))
    local isHeal = not issecret(action) and action == "HEAL"
    report(kind, ("%s at +%.1fs: flags %s, amount %s, school %s"):format(unit, GetTime() - watchStart,
        describe(flags), describe(amount), describe(school)), isHeal and MAX_HEAL_LINES or nil)
end

local LOG_KINDS = { SPELL_AURA_REMOVED = true, SPELL_DISPEL = true, SPELL_PERIODIC_HEAL = true }

-- The old global, or C_CombatLog's version on clients that moved it.
local function combatLogInfoFn()
    if type(CombatLogGetCurrentEventInfo) == "function" then return CombatLogGetCurrentEventInfo, "CombatLogGetCurrentEventInfo" end
    if type(C_CombatLog) == "table" and type(C_CombatLog.GetCurrentEventInfo) == "function" then
        return C_CombatLog.GetCurrentEventInfo, "C_CombatLog.GetCurrentEventInfo"
    end
end

local function onCombatLog()
    local r = { pcall((combatLogInfoFn())) }
    if not r[1] then return report("combat log", "ERROR " .. tostring(r[2])) end
    local sub, srcGUID, destName, spellName = r[3], r[5], r[10], r[14]
    if issecret(sub) then return report("combat log", "subevent SECRET") end
    if not LOG_KINDS[sub] then return end
    local fromMe = not issecret(srcGUID) and srcGUID == UnitGUID("player")
    if sub == "SPELL_DISPEL" then
        -- the dispelled aura is the extra spell (r[17] = its name)
        report(sub, ("%s removed %s from %s"):format(describe(spellName), describe(r[17]), describe(destName)))
    elseif fromMe or issecret(srcGUID) then
        local extra = sub == "SPELL_PERIODIC_HEAL"
            and (" for %s, overheal %s"):format(describe(r[16]), describe(r[17])) or ""
        report(sub, ("%s on %s%s%s"):format(describe(spellName), describe(destName), extra,
            issecret(srcGUID) and " (source SECRET)" or ""))
    end
end

watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_AURA" then
        onUnitAura(...)
    elseif event == "UNIT_COMBAT" then
        onUnitCombat(...)
    else
        onCombatLog()
    end
end)

local function startWatch()
    watcher:UnregisterAllEvents()
    watchToken, watchLines, perKind, watchStart = watchToken + 1, 0, {}, GetTime()
    local token = watchToken
    local okAura = pcall(watcher.RegisterEvent, watcher, "UNIT_AURA")
    say("UNIT_AURA listener: " .. (okAura and "registered" or "can't register"))
    local okCombat = pcall(watcher.RegisterEvent, watcher, "UNIT_COMBAT")
    say("UNIT_COMBAT listener: " .. (okCombat and "registered" or "can't register"))
    if type(C_CombatLog) == "table" then
        local names = {}
        local ok = pcall(function() for k in pairs(C_CombatLog) do names[#names + 1] = tostring(k) end end)
        table.sort(names)
        say("C_CombatLog: " .. (not ok and "can't list" or #names == 0 and "empty" or table.concat(names, ", ")))
    else
        say("C_CombatLog: missing")
    end
    local infoFn, infoName = combatLogInfoFn()
    local okLog = infoFn and pcall(watcher.RegisterEvent, watcher, "COMBAT_LOG_EVENT_UNFILTERED")
    say("combat log: " .. (not infoFn and "no event info function"
        or (infoName .. (okLog and ", registered" or ", can't register"))))
    say(("listening %ds: remove or let a HoT expire, in and out of combat"):format(WATCH_SECONDS))
    C_Timer.After(WATCH_SECONDS, function()
        if token == watchToken then stopWatch("time up") end
    end)
end

-- Out of combat: your own auras on the group, with their instance ids, to match removals against later.
local function listOwnAuras()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return say("own auras: no aura API") end
    wipe(knownAuraIDs)
    for _, unit in ipairs(ns.groupUnits()) do
        local key = ns.unitKey(unit) or unit
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
            if not ok then return say("own aura on " .. key .. ": ERROR " .. tostring(aura)) end
            if not aura then break end
            local id = aura.auraInstanceID
            if not issecret(id) and id and not issecret(aura.name) then
                knownAuraIDs[id] = aura.name .. " on " .. key
            end
            say(("own aura on %s: %s id %s expires %s"):format(key, describe(aura.name), describe(id),
                describe(aura.expirationTime)))
        end
    end
end

-- What Forever lets this addon read right now.
local function probe()
    ns.anyActive() -- drops expired HoTs first
    say(("probe, %s combat"):format(ns.inCombat() and "IN" or "out of"))
    say("UnitHealthMax(player): " .. describe(UnitHealthMax("player")))
    say("UnitGetIncomingHeals: " .. (UnitGetIncomingHeals and describe(UnitGetIncomingHeals("player")) or "missing"))
    if ns.inCombat() then
        say("own auras: not read in combat (it taints)")
    else
        listOwnAuras()
    end
    if GetSpellCritChance then
        local function crit(school)
            if ns.inCombat() then return "not read in combat" end
            local ok, value = pcall(GetSpellCritChance, school)
            if ok and type(value) == "number" and not issecret(value) then return ("%.2f%%"):format(value) end
            return describe(value)
        end
        local holy, nature = crit(ns.SCHOOL_HOLY), crit(ns.SCHOOL_NATURE)
        local kept = ns.critChance({ school = ns.SCHOOL_NATURE })
        say(("spell crit: holy %s, nature %s; kept for nature %s%s"):format(holy, nature,
            kept and ("%.2f%%"):format(kept * 100) or "none", ns.db.includeCrits and "" or " (option off)"))
    else
        say("spell crit: GetSpellCritChance missing")
    end
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
    startWatch()
end

-- Every metric the game's addon profiler offers, for this addon and for all addons.
local function perf()
    local P = C_AddOnProfiler
    if type(P) ~= "table" or type(P.GetAddOnMetric) ~= "function" then
        return say("perf: the addon profiler isn't available on this client")
    end
    if type(P.IsEnabled) == "function" then
        local ok, on = pcall(P.IsEnabled)
        say("perf: profiler " .. (not ok and "state unknown" or on and "on" or "off"))
    end
    local hots, overlays = 0, 0
    for _, byName in pairs(ns.hots) do for _ in pairs(byName) do hots = hots + 1 end end
    for _ in pairs(ns.overlays) do overlays = overlays + 1 end
    say(("perf: %s combat, %d HoT(s) tracked, %d health bars watched, drain %s"):format(
        ns.inCombat() and "in" or "out of", hots, overlays, ns.db.drain))
    local metrics = Enum and Enum.AddOnProfilerMetric
    if type(metrics) ~= "table" then return say("perf: no metric list (Enum.AddOnProfilerMetric)") end
    local list = {}
    for name, id in pairs(metrics) do list[#list + 1] = { name = name, id = id } end
    table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local function fmt(ok, v)
        if not ok then return "error" end
        if type(v) == "number" and not issecret(v) then return ("%.4f"):format(v) end
        return describe(v)
    end
    for _, m in ipairs(list) do
        local mine = fmt(pcall(P.GetAddOnMetric, addonName, m.id))
        local all = type(P.GetOverallMetric) == "function" and fmt(pcall(P.GetOverallMetric, m.id)) or "n/a"
        say(("perf %s: %s (all addons %s)"):format(m.name, mine, all))
    end
end

local HELP = {
    "/dil - options window",
    "/dil toggle - turn the blocks on or off",
    "/dil test - sample blocks on every frame found",
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
    elseif cmd == "perf" then
        perf()
    elseif cmd == "probe" then
        probe()
    elseif cmd == "debug" then
        db.debug = not db.debug
        say("debug " .. (db.debug and "on" or "off"))
    else
        for _, line in ipairs(HELP) do say(line) end
    end
end
