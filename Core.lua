local addonName, ns = ...

-- Tracks your own HoTs per group member and answers "how much healing is left on this unit".
--
-- What Forever lets addons read (DoesItDie's findings, confirmed in game for this addon):
--   readable: your own cast events (SENT names the target by full name, SUCCEEDED gives the spell),
--             spell descriptions, your stats out of combat, your own auras out of combat.
--   secret:   unit health and max health, incoming heals (fine: they only go into StatusBars).
--   blocked:  auras in combat. Even a pcall'd read taints the addon, so it never reads them in combat.

local issecret = issecretvalue or function() return false end
local GetTime = GetTime

ns.hots = {}             -- [unitKey] = { [spellName] = hot }
local pendingTarget = {} -- [castGUID] = target name from UNIT_SPELLCAST_SENT
local parsed = {}        -- [spellID] = info, or false (not a HoT)
local bonusHealing = 0   -- cached out of combat

local function trace(msg)
    if ns.db and ns.db.debug then print("|cff40d090DIL|r " .. msg) end
end
ns.trace = trace

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------

-- Stable key for a group member: the full name as cast events report it. On Forever that's
-- "First Last" (GetUnitName(unit, true); UnitName returns the last name where the realm usually is).
-- Falls back to "Name-Realm" or "Name". nil when the name is secret.
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

-- The units a party-wide HoT lands on: the whole party, or the target's subgroup in a raid.
-- Dead players are left out, and players the game reports out of your range when it says so.
local function partyOf(unit)
    local members = {}
    local okGroup, inGroup = pcall(function()
        return UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit) ~= nil
    end)
    if not okGroup or not plain(inGroup) or not inGroup then return { unit } end -- outside your group: just them
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
            local ok, same = pcall(UnitIsUnit, "raid" .. i, unit)
            if ok and plain(same) and same then group = select(3, GetRaidRosterInfo(i)) break end
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

-- The group member a cast went to. SENT gives the full name ("Daft Druid"), or nothing for
-- self/auto self-cast. Exact full-name matches win; the first-name match is the fallback; the
-- friendly target, then yourself, when SENT names nobody.
-- Friendly units outside the group a HoT can go to and a frame can show: target, focus, mouseover.
local SINGLE_CANDIDATES = { "target", "focus", "mouseover" }

local function friendly(unit)
    if not UnitExists(unit) then return false end
    local ok, isFriend = pcall(UnitIsFriend, "player", unit)
    return ok and plain(isFriend) and isFriend
end

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

local function hotInfo(spellID)
    if parsed[spellID] ~= nil then return parsed[spellID] or nil end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not name and GetSpellInfo then name = GetSpellInfo(spellID) end
    local descFn = (C_Spell and C_Spell.GetSpellDescription) or GetSpellDescription
    local desc = descFn and descFn(spellID)
    if not name or not desc or desc == "" or issecret(desc) then
        return nil -- not loaded yet: try again next cast (not a HoT is the usual case, so no trace)
    end
    local amount, duration, direct, party = ns.parseHot(desc)
    local override = ns.SPELLS[name] or {}
    if not amount or override.skip then
        parsed[spellID] = false
        return nil
    end
    local tick = override.tick or ns.DEFAULT_TICK
    local ticks = math.max(1, math.floor(duration / tick + 0.5))
    local info = {
        name = name, spellID = spellID, amount = amount, duration = duration, direct = direct,
        party = party or override.party, tick = tick, ticks = ticks,
        weights = tickWeights(ticks, override.shape),
        coef = override.coef or math.min(duration / 15, 1),
    }
    parsed[spellID] = info
    trace(("parsed %s (%d): %d over %ss in %d ticks%s%s"):format(name, spellID, amount, duration, ticks,
        direct > 0 and (", upfront " .. direct) or "", info.party and ", party-wide" or ""))
    return info
end
ns.hotInfo = hotInfo

function ns.cacheBonusHealing()
    if InCombatLockdown() or not GetSpellBonusHealing then return end
    local ok, value = pcall(GetSpellBonusHealing)
    if ok and plain(value) then bonusHealing = value end
end
function ns.bonusHealing() return bonusHealing end

-- Average healing per tick for a new cast: the damage meter's learned size when there is one,
-- else the tooltip plus +healing x coefficient. Then the scale setting.
function ns.averageTick(info)
    local learned = ns.db.learned[info.spellID]
    local avg
    if learned and learned.tick then
        avg = learned.tick
    else
        local total = info.amount
        if ns.db.useBonusHealing then total = total + bonusHealing * info.coef end
        avg = total / info.ticks
    end
    return avg * (ns.db.scale / 100)
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------

-- Every application, kept a while for the damage meter tally after combat (Meter.lua).
ns.apps = {}
ns.castLog = {}      -- { spellID, time } of casts with an upfront heal
ns.untracked = {}    -- [spellID] = time of a cast that went to nobody in the group

local function endApp(hot, now)
    if hot and hot.app and not hot.app.ended then hot.app.ended = now end
end

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
    if old then endApp(old, now) serial = old.serial end
    -- A recast replaces the old one (these HoTs refresh, they don't stack).
    local app = { spellID = info.spellID, info = info, start = now }
    ns.apps[#ns.apps + 1] = app
    ns.hots[key][info.name] = {
        name = info.name, spellID = info.spellID, interval = info.tick, ticks = info.ticks, amounts = amounts,
        expires = now + info.duration, duration = info.duration, app = app, serial = serial,
    }
    trace(("%s on %s (%s): %.0f per tick"):format(info.name, key, unit, avg))
    if ns.onApplied then ns.onApplied(key) end
end

function ns.onCastSent(targetName, castGUID)
    if castGUID then pendingTarget[castGUID] = targetName or "" end
end

function ns.onCastSucceeded(castGUID, spellID)
    local targetName = castGUID and pendingTarget[castGUID]
    if castGUID then pendingTarget[castGUID] = nil end
    local info = hotInfo(spellID)
    if not info then return end
    local now = GetTime()
    local unit = resolveCastUnit(targetName)
    if not unit then
        ns.untracked[spellID] = now
        return
    end
    if info.direct > 0 then ns.castLog[#ns.castLog + 1] = { spellID = spellID, time = now } end
    if info.party then
        for _, member in ipairs(partyOf(unit)) do apply(member, info, now) end
    else
        apply(unit, info, now)
    end
    ns.startTicker()
end

-- Refinement from auras, out of combat only: in combat Forever makes them secret, and even a pcall'd
-- read taints the addon. Any error turns reads off until combat ends, as a safety net.
local auraBlocked = false
function ns.unblockAuras() auraBlocked = false end

local function inCombat() return InCombatLockdown() or UnitAffectingCombat("player") end
ns.inCombat = inCombat

local function auraScan(unit, byName)
    if auraBlocked or inCombat() then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
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
    local now = GetTime()
    for name, hot in pairs(byName) do
        local expires = seen[name]
        if expires and expires > 0 then
            hot.expires, hot.auraSeen = expires, true
        elseif hot.auraSeen then
            endApp(hot, now)
            byName[name] = nil -- confirmed earlier, cleanly absent now: dispelled or cancelled
        end
    end
end

-- Ticks still to land, from the expiry (which the aura scan can correct).
local function ticksLeft(hot, now)
    local left = hot.expires - now
    if left <= 0 then return 0, 0 end
    return math.max(0, math.min(hot.ticks, math.ceil(left / hot.interval - 0.05))), left
end

-- Healing still to come from one HoT. Smooth drain eats into the next tick as it approaches.
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

-- total (plain number), parts ({ name, amount } in a stable order), tickSerial (goes up as ticks land).
function ns.remainingFor(unit)
    local key = ns.unitKey(unit)
    local byName = key and ns.hots[key]
    if not byName then return 0 end
    local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
    if okDead and plain(dead) and dead then
        local now = GetTime()
        for _, hot in pairs(byName) do endApp(hot, now) end
        ns.hots[key] = nil
        return 0
    end
    auraScan(unit, byName)
    local now, total, parts, serial = GetTime(), 0, {}, 0
    local smooth = ns.db.drain == "smooth"
    for name, hot in pairs(byName) do
        local amount = remainingOf(hot, now, smooth)
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

-- Old applications and casts aren't needed once no fight can still count them.
local KEEP_SECONDS = 120
function ns.pruneLogs()
    if inCombat() then return end
    local cutoff = GetTime() - KEEP_SECONDS
    local apps = {}
    for _, app in ipairs(ns.apps) do
        if (app.ended or (app.start + app.info.duration)) > cutoff then apps[#apps + 1] = app end
    end
    ns.apps = apps
    local casts = {}
    for _, c in ipairs(ns.castLog) do if c.time > cutoff then casts[#casts + 1] = c end end
    ns.castLog = casts
    for id, t in pairs(ns.untracked) do if t <= cutoff then ns.untracked[id] = nil end end
end

---------------------------------------------------------------------------
-- Ticker and events
---------------------------------------------------------------------------

local ticker
function ns.startTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(ns.REFRESH, function()
        ns.redraw()
        if not ns.anyActive() and not ns.testMode then ticker:Cancel() ticker = nil ns.redraw() end
    end)
    ns.redraw()
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
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end
        DoesItLiveDB = DoesItLiveDB or {}
        local db = DoesItLiveDB
        if type(db.scale) == "number" and db.scale < 10 then db.scale = math.floor(db.scale * 100 + 0.5) end -- 0.1.0 stored a factor
        db.color = nil -- 0.1.0's color table, replaced by fillColor
        for k, v in pairs(ns.DEFAULTS) do
            if db[k] == nil then db[k] = copyDefault(v) end
        end
        ns.db = db
        if ns.registerOptions then ns.registerOptions() end
    elseif event == "PLAYER_LOGIN" then
        ns.cacheBonusHealing()
        ns.rescan()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ns.combatStart = GetTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.unblockAuras()
        ns.cacheBonusHealing()
        if ns.learnAfterCombat and ns.combatStart then ns.learnAfterCombat(ns.combatStart, GetTime()) end
        ns.combatStart = nil
        ns.rescan()
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.rescan()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, targetName, castGUID = ...
        if ns.db.enabled then ns.onCastSent(targetName, castGUID) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        if ns.db.enabled then ns.onCastSucceeded(castGUID, spellID) end
    end
end)
