local addonName, ns = ...

-- Tracks your own HoTs per unit and answers "how much healing is left on this unit".
--
-- What Forever lets addons read:
--   readable: your own cast events (SENT names the target by full name, SUCCEEDED gives the spell),
--             spell descriptions, max health out of combat, your own auras out of combat,
--             the timing of heals on units (UNIT_COMBAT).
--   secret:   max health in combat, incoming heals, heal amounts (only ever passed to StatusBars),
--             aura updates in combat.
--   blocked:  reading auras in combat: even a pcall'd read taints the addon.

local issecret = issecretvalue or function() return false end
local GetTime = GetTime

ns.hots = {}             -- [unitKey] = { [spellName] = hot }
local pendingTarget = {} -- [castGUID] = { name = target name from UNIT_SPELLCAST_SENT, time = sent at }
local parsed = {}        -- [spellID] = info from the last readable tooltip, or false (not a HoT)

local function trace(msg)
    if ns.db and ns.db.debug then print("|cff40d090DIL|r " .. msg) end
end
ns.trace = trace

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------

-- Key for a unit: the full name as cast events report it, "First Last" on Forever (UnitName returns the
-- last name where the realm usually is). Falls back to "Name-Realm" or "Name"; nil when the name is secret.
function ns.unitKey(unit)
    if not unit or not UnitExists(unit) then return nil end
    if GetUnitName then
        local okFull, full = pcall(GetUnitName, unit, true)
        if okFull and full and not issecret(full) and full ~= "" then return full end
    end
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or not name or issecret(name) then return nil end
    if realm and not issecret(realm) and realm ~= "" then return name .. "-" .. realm end
    return name
end

function ns.groupUnits()
    local list = { "player" }
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
    end
    return list
end

local function plain(v) return v ~= nil and not issecret(v) end

local function sameUnit(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and plain(same) and same
end

local function inMyGroup(unit)
    local ok, inGroup = pcall(function()
        return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit) ~= nil
    end)
    return ok and plain(inGroup) and inGroup
end

-- The units a party-wide HoT lands on: the whole party, or the target's subgroup in a raid.
-- Dead players are left out, and players the game reports out of your range when it says so.
local function partyOf(unit)
    local members = {}
    if not inMyGroup(unit) then return { unit } end -- outside your group: just them
    local function add(u)
        local okDead, dead = pcall(UnitIsDeadOrGhost, u)
        if okDead and plain(dead) and dead then return end
        if UnitInRange then
            local okRange, inRange, checked = pcall(UnitInRange, u)
            if okRange and plain(inRange) and plain(checked) and checked and not inRange then return end
        end
        members[#members + 1] = u
    end
    if IsInRaid() then
        local group
        for i = 1, GetNumGroupMembers() do
            if sameUnit("raid" .. i, unit) then group = select(3, GetRaidRosterInfo(i)) break end
        end
        for i = 1, GetNumGroupMembers() do
            if not group or select(3, GetRaidRosterInfo(i)) == group then add("raid" .. i) end
        end
    else
        for _, u in ipairs(ns.groupUnits()) do add(u) end
    end
    return members
end

-- Fallback match when no full name matches exactly: the unit's first name followed by a space or
-- a dash in the SENT text. Can pick the wrong one of two groupmates sharing a first name.
local function startsWithName(targetName, key)
    local first = key:match("^([^%s%-]+)")
    if not first then return false end
    local nextChar = targetName:sub(#first + 1, #first + 1)
    return targetName:sub(1, #first) == first and (nextChar == "" or nextChar == " " or nextChar == "-")
end

-- Friendly units outside the group a HoT can go to.
local SINGLE_CANDIDATES = { "target", "focus", "mouseover" }

local function friendly(unit)
    if not UnitExists(unit) then return false end
    local ok, isFriend = pcall(UnitIsFriend, "player", unit)
    return ok and plain(isFriend) and isFriend
end

-- The unit a cast went to: an exact full-name match, else a first-name match. When SENT names nobody,
-- the friendly target, else yourself.
local function resolveCastUnit(targetName)
    if targetName and not issecret(targetName) and targetName ~= "" then
        local candidates = ns.groupUnits()
        for _, unit in ipairs(SINGLE_CANDIDATES) do
            if friendly(unit) then candidates[#candidates + 1] = unit end
        end
        local fallback
        for _, unit in ipairs(candidates) do
            local key = ns.unitKey(unit)
            if key == targetName then return unit end
            if key and not fallback and startsWithName(targetName, key) then fallback = unit end
        end
        if fallback then
            trace(("cast target '%s' matched by first name only"):format(targetName))
            return fallback
        end
        trace(("cast target '%s' isn't in your group, target or focus, skipped"):format(targetName))
        return nil
    end
    if friendly("target") then return "target" end
    return "player"
end

---------------------------------------------------------------------------
-- Spell descriptions
---------------------------------------------------------------------------

local function num(text) return tonumber((text:gsub(",", ""))) end

-- English patterns from Forever's own tooltips:
--   Renew         "Heals the target of 830 damage over 15 sec."
--   Rejuvenation  "Heals the target for 776 over 12 sec."
--   Regrowth      "Heals a friendly target for 965 to 1077 and another 994 over 21 sec."
--   Riptide       "Heals a friendly target for 799 to 883, an additional 805 over 15 sec, ..."
--   Wild Growth   "Heals the target and their party for 679 over 7 sec. ..."
local PATTERNS = {
    "and another ([%d,]+) over ([%d%.]+) sec",
    "an additional ([%d,]+) over ([%d%.]+) sec",
    "of ([%d,]+) damage over ([%d%.]+) sec",
    "for ([%d,]+) over ([%d%.]+) sec",
}

-- amount, duration, direct (average of the upfront heal, 0 if none), party
function ns.parseHot(desc)
    if not desc or issecret(desc) or not desc:find("^Heals") then return nil end
    for _, pattern in ipairs(PATTERNS) do
        local amount, secs = desc:match(pattern)
        if amount then
            local low, high = desc:match("for ([%d,]+) to ([%d,]+)")
            local direct = low and (num(low) + num(high)) / 2 or 0
            return num(amount), tonumber(secs), direct, desc:find("their party") ~= nil
        end
    end
end

-- Per-tick weights averaging 1: flat, or a straight line from shape[1] to shape[2].
local function tickWeights(ticks, shape)
    local weights, sum = {}, 0
    for k = 1, ticks do
        local w = 1
        if shape and ticks > 1 then w = shape[1] + (shape[2] - shape[1]) * (k - 1) / (ticks - 1) end
        weights[k], sum = w, sum + w
    end
    for k = 1, ticks do weights[k] = weights[k] * ticks / sum end
    return weights
end

-- Read on every cast; the last readable tooltip stands in when it can't be read.
local function hotInfo(spellID)
    local cached = parsed[spellID]
    if cached == false then return nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    local descFn = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    local desc = descFn and descFn(spellID)
    if not name or not desc or issecret(desc) or desc == "" then
        return cached
    end
    if cached and cached.desc == desc then return cached end
    local amount, duration, direct, party = ns.parseHot(desc)
    local override = ns.SPELLS[name] or {}
    if not amount or override.skip then
        parsed[spellID] = false
        return nil
    end
    local tick = override.tick or ns.DEFAULT_TICK
    local ticks = math.max(1, math.floor(duration / tick + 0.5))
    local info = {
        name = name, spellID = spellID, desc = desc, amount = amount, duration = duration, direct = direct,
        party = party or override.party, tick = tick, ticks = ticks, school = override.school,
        weights = tickWeights(ticks, override.shape),
    }
    parsed[spellID] = info
    trace(("parsed %s (%d): %d over %ss in %d ticks%s%s"):format(name, spellID, amount, duration, ticks,
        direct > 0 and (", upfront " .. direct) or "", info.party and ", party-wide" or ""))
    return info
end
ns.hotInfo = hotInfo

---------------------------------------------------------------------------
-- Crit chance
---------------------------------------------------------------------------
-- Read out of combat only; in combat the last reading is used.

local critBySchool = {} -- [school] = crit chance in %

local function readCrit()
    if InCombatLockdown() or UnitAffectingCombat("player") or not GetSpellCritChance then return end
    local changed = {}
    for school = 2, 7 do
        local ok, value = pcall(GetSpellCritChance, school)
        if ok and plain(value) and type(value) == "number" and value ~= critBySchool[school] then
            critBySchool[school] = value
            changed[#changed + 1] = ("%d: %.2f%%"):format(school, value)
        end
    end
    if #changed > 0 then trace("crit chance by school, " .. table.concat(changed, ", ")) end
end
ns.readCrit = readCrit

-- Crit chance (0 to 1) for a spell: its school's, else the highest known. nil when never read.
function ns.critChance(info)
    local value = info and info.school and critBySchool[info.school]
    if not value then
        for _, v in pairs(critBySchool) do value = math.max(value or 0, v) end
    end
    return value and value / 100
end

function ns.averageTick(info)
    local tick = info.amount / info.ticks
    local crit = ns.db.includeCrits and ns.critChance(info)
    if crit then tick = tick * (1 + crit * (ns.CRIT_MULTIPLIER - 1)) end
    return tick * (ns.db.scale / 100)
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

local function apply(unit, info, now)
    local key = ns.unitKey(unit)
    if not key then
        trace(info.name .. ": target's name isn't readable, skipped")
        return
    end
    local avg = ns.averageTick(info)
    local amounts, serial = {}, 0
    for k = 1, info.ticks do amounts[k] = avg * info.weights[k] end
    ns.hots[key] = ns.hots[key] or {}
    local old = ns.hots[key][info.name]
    if old then serial = old.serial end
    -- HoTs refresh rather than stack: a recast replaces the old one.
    ns.hots[key][info.name] = {
        name = info.name, spellID = info.spellID, interval = info.tick, ticks = info.ticks, amounts = amounts,
        expires = now + info.duration, duration = info.duration, serial = serial,
        nextTick = 1, seen = 0, -- next tick index to expect, ticks seen landing
    }
    trace(("%s on %s (%s): %.0f per tick"):format(info.name, key, unit, avg))
    if ns.onApplied then ns.onApplied(key) end
end

-- Casts that fail or get interrupted never reach SUCCEEDED: their entries are dropped after this long.
local PENDING_SECONDS = 30

function ns.onCastSent(targetName, castGUID)
    if not castGUID then return end
    local cutoff = GetTime() - PENDING_SECONDS
    for guid, pending in pairs(pendingTarget) do
        if pending.time < cutoff then pendingTarget[guid] = nil end
    end
    pendingTarget[castGUID] = { name = targetName or "", time = GetTime() }
end

function ns.onCastSucceeded(castGUID, spellID)
    local pending = castGUID and pendingTarget[castGUID]
    local targetName = pending and pending.name
    if castGUID then pendingTarget[castGUID] = nil end
    local info = hotInfo(spellID)
    if not info then return end
    trace(("%s cast, SENT named '%s'"):format(info.name, tostring(targetName)))
    local now = GetTime()
    local unit = resolveCastUnit(targetName)
    if not unit then return end
    if info.party then
        for _, member in ipairs(partyOf(unit)) do apply(member, info, now) end
    else
        apply(unit, info, now)
    end
    ns.startTicker()
end

-- Aura reads correct expiries and catch removals, out of combat only (in combat they taint). An error turns
-- them off until combat ends.
local auraBlocked = false
function ns.unblockAuras() auraBlocked = false end

local function inCombat() return InCombatLockdown() or UnitAffectingCombat("player") end
ns.inCombat = inCombat

local auraScannedAt = {} -- [unitKey] = GetTime() of the last read

local function auraScan(unit, key, byName)
    if auraBlocked or inCombat() then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local last = auraScannedAt[key]
    if last and GetTime() - last < ns.AURA_RESCAN then return end
    auraScannedAt[key] = GetTime()
    local seen = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
        if not ok then
            auraBlocked = true
            trace("aura read failed, off until combat ends")
            return
        end
        if not aura then break end
        local name, expires = aura.name, aura.expirationTime
        if issecret(name) or issecret(expires) then return end
        seen[name] = expires
    end
    for name, hot in pairs(byName) do
        local expires = seen[name]
        if expires and expires > 0 then
            hot.expires, hot.auraSeen = expires, true
        elseif hot.auraSeen then
            byName[name] = nil -- seen before, gone now: dispelled or cancelled
        end
    end
end

local function ticksLeft(hot, now)
    local left = hot.expires - now
    if left <= 0 then return 0, 0 end
    return math.max(0, math.min(hot.ticks, math.ceil(left / hot.interval - 0.05))), left
end

-- Smooth drain eats into the next tick as it approaches.
local function remainingOf(hot, now, smooth)
    local n, left = ticksLeft(hot, now)
    if n ~= hot.lastLeft then
        if hot.lastLeft and n < hot.lastLeft then hot.serial = hot.serial + 1 end
        hot.lastLeft = n
    end
    if n == 0 then return 0 end
    local first = hot.ticks - n + 1
    local total = 0
    for k = first, hot.ticks do total = total + hot.amounts[k] end
    if smooth then
        local untilNext = left - (n - 1) * hot.interval
        local frac = math.max(0, math.min(1, untilNext / hot.interval))
        total = total - hot.amounts[first] * (1 - frac)
    end
    return total
end

---------------------------------------------------------------------------
-- Tick matching
---------------------------------------------------------------------------
-- UNIT_COMBAT reports each heal on a unit with readable timing, but no amount or spell. A heal close to a HoT's
-- due tick is taken as that tick. Once a HoT's tick has been seen, a due tick with no heal means it was
-- dispelled or cancelled.

local function dueAt(hot, k) return hot.expires - (hot.ticks - k) * hot.interval end

-- One token per person, so a heal isn't counted twice: group tokens for the group, target or focus for
-- anyone else. Returns accept, isGroupToken.
local function healToken(unit)
    if unit == "player" then return true, true end
    if unit:find("^raid%d") then return IsInRaid() and not sameUnit(unit, "player"), true end
    if unit:find("^party%d") then return not IsInRaid(), true end
    if unit == "target" then return not inMyGroup(unit), false end
    if unit == "focus" then return not inMyGroup(unit) and not sameUnit("focus", "target"), false end
    return false
end

function ns.onHeal(unit)
    if not next(ns.hots) or type(unit) ~= "string" or issecret(unit) then return end
    local accept, group = healToken(unit)
    if not accept then return end
    local key = ns.unitKey(unit)
    local byName = key and ns.hots[key]
    if not byName then return end
    local now, window = GetTime(), ns.TICK_WINDOW
    local best, bestName, bestK, bestOff
    for name, hot in pairs(byName) do
        for k = hot.nextTick, hot.ticks do
            local off = now - dueAt(hot, k)
            if off < -window then break end -- later ticks are further off still
            if off <= window and (not best or math.abs(off) < math.abs(bestOff)) then
                best, bestName, bestK, bestOff = hot, name, k, off
            end
        end
    end
    if not best then return end
    -- A cast's first tick can be off by latency, so it syncs within the full window.
    local syncWindow = best.seen == 0 and window or ns.TICK_SYNC_WINDOW
    local synced = math.abs(bestOff) <= syncWindow and not best.auraSeen
    best.nextTick, best.seen = bestK + 1, best.seen + 1
    -- Target and focus can change, so only HoTs heard through group tokens are judged for missed ticks.
    best.heardInGroup = group
    if synced then best.expires = best.expires + bestOff end
    trace(("TICK %s on %s (%d/%d, %+.2fs%s)"):format(bestName, key, bestK, best.ticks, bestOff,
        synced and ", synced" or ""))
end

-- True when the HoT's next tick is overdue, meaning it's gone.
local function missedTick(hot, unit, name, key, now)
    if hot.seen == 0 or not hot.heardInGroup or hot.nextTick > hot.ticks then return false end
    local due = dueAt(hot, hot.nextTick)
    -- After a hitch, wait a frame: the heal may be in events not handled yet.
    local sinceLast = now - (hot.missCheckedAt or now)
    hot.missCheckedAt = now
    if sinceLast > 0.25 then return false end
    if now <= due + ns.TICK_MISS_AFTER then return false end
    -- Out of sight, the game may not send heals at all.
    local okVisible, visible = pcall(UnitIsVisible, unit)
    if not (okVisible and plain(visible) and visible) then
        hot.nextTick = hot.nextTick + 1
        return false
    end
    trace(("MISS %s on %s: tick %d/%d didn't land, removed"):format(name, key, hot.nextTick, hot.ticks))
    return true
end

-- total (plain number), parts ({ name, amount } in a stable order), tickSerial (goes up as ticks land).
-- key: the unit's key when the caller already has it.
function ns.remainingFor(unit, key)
    key = key or ns.unitKey(unit)
    local byName = key and ns.hots[key]
    if not byName then return 0 end
    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if okDead and plain(dead) and dead then
        ns.hots[key] = nil
        return 0
    end
    auraScan(unit, key, byName)
    local now, total, parts, serial = GetTime(), 0, {}, 0
    local smooth = ns.db.drain == "smooth"
    for name, hot in pairs(byName) do
        local amount = missedTick(hot, unit, name, key, now) and 0 or remainingOf(hot, now, smooth)
        serial = serial + hot.serial
        if amount <= 0 then
            byName[name] = nil
        else
            total = total + amount
            parts[#parts + 1] = { name = name, amount = amount }
        end
    end
    table.sort(parts, function(a, b) return a.name < b.name end)
    if not next(byName) then ns.hots[key] = nil end
    return total, parts, serial
end

-- Also drops expired HoTs on units no frame is showing, so the ticker can stop.
function ns.anyActive()
    local now = GetTime()
    for key, byName in pairs(ns.hots) do
        for name, hot in pairs(byName) do
            if hot.expires <= now then byName[name] = nil end
        end
        if not next(byName) then ns.hots[key] = nil end
    end
    return next(ns.hots) ~= nil
end

---------------------------------------------------------------------------
-- Ticker and events
---------------------------------------------------------------------------

local ticker, tickerRate
local function refreshRate() return ns.db.drain == "smooth" and ns.REFRESH_SMOOTH or ns.REFRESH_TICKS end

function ns.startTicker()
    if ticker then return end
    tickerRate = refreshRate()
    ticker = C_Timer.NewTicker(tickerRate, function()
        ns.redraw()
        if not ns.anyActive() and not ns.testMode then ticker:Cancel() ticker = nil ns.redraw() end
    end)
    ns.redraw()
end

function ns.updateTickerRate()
    if ticker and tickerRate ~= refreshRate() then
        ticker:Cancel()
        ticker = nil
        ns.startTicker()
    end
end

-- Frame addons may build their buttons just after the event: look again a moment later (once per burst).
local rescanPending = false
local function rescanNowAndSoon()
    ns.rescan()
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(1, function()
        rescanPending = false
        ns.rescan()
    end)
end

local function copyDefault(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copyDefault(x) end
    return t
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterEvent("UNIT_COMBAT")

-- What can change crit chance. Some may not exist on this client.
local CRIT_EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
}
local isCritEvent = {}
for _, name in ipairs(CRIT_EVENTS) do
    if pcall(events.RegisterEvent, events, name) then isCritEvent[name] = true end
end
events:RegisterUnitEvent("UNIT_AURA", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        DoesItLiveDB = DoesItLiveDB or {}
        local db = DoesItLiveDB
        for k, v in pairs(ns.DEFAULTS) do
            if db[k] == nil then db[k] = copyDefault(v) end
        end
        ns.db = db
        if ns.registerOptions then ns.registerOptions() end
    elseif event == "PLAYER_LOGIN" then
        readCrit()
        rescanNowAndSoon()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        rescanNowAndSoon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.unblockAuras()
        readCrit()
        C_Timer.After(1, readCrit) -- the game may still report combat for a moment
        ns.rescan()
    elseif event == "UNIT_AURA" or isCritEvent[event] then
        readCrit()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, targetName, castGUID = ...
        if ns.db.enabled then ns.onCastSent(targetName, castGUID) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        if ns.db.enabled then ns.onCastSucceeded(castGUID, spellID) end
    elseif event == "UNIT_COMBAT" then
        local unit, action = ...
        if ns.db and ns.db.enabled and not issecret(action) and action == "HEAL" then ns.onHeal(unit) end
    end
end)
