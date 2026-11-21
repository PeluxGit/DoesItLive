local _, ns = ...

-- Learning real tick sizes from the damage meter, after each fight (approach from DoesItDie's learnFromMeter).
--
-- In combat nothing about the heals can be read, but after combat Forever's damage meter gives readable
-- per-spell healing totals for the fight. Each spell's total is compared with what the tooltip predicts for
-- the ticks this addon counted in that fight (plus Regrowth-style upfront heals), and the ratio turns the
-- tooltip's tick into a real one, which already includes +healing and talents.
--
-- The meter counts effective healing, so overhealing makes a fight read low. Tooltips leave out +healing,
-- so the real tick is never below the tooltip's: a fight that reads below it had overhealing (or a HoT was
-- dispelled) and teaches nothing. Partly overhealed fights still read a bit low; repeated fights even it out.

local issecret = issecretvalue or function() return false end
local function trace(msg) ns.trace(msg) end

local MIN_FACTORS = 2                    -- at least two ticks' worth this fight
local RATIO_MIN, RATIO_MAX = 0.95, 3.0   -- vs the tooltip; outside this something else got mixed in
local WEIGHT_CAP = 20                    -- older fights count as at most this many ticks, so gear changes catch up
local TRIES, RETRY_SECONDS = 20, 0.5

-- Per spell, what the addon counted between combatStart and combatEnd.
local function tally(combatStart, combatEnd)
    local bySpell = {}
    local function entry(app)
        local t = bySpell[app.spellID]
        if not t then
            t = { info = app.info, factors = 0, ticks = 0, directs = 0 }
            bySpell[app.spellID] = t
        end
        return t
    end
    for _, app in ipairs(ns.apps) do
        local info = app.info
        local stop = math.min(app.ended or math.huge, app.start + info.duration + 0.1)
        for k = 1, info.ticks do
            local at = app.start + k * info.tick
            if at > stop then break end
            if at >= combatStart and at <= combatEnd then
                local t = entry(app)
                t.factors = t.factors + info.weights[k]
                t.ticks = t.ticks + 1
            end
        end
    end
    for _, cast in ipairs(ns.castLog) do
        local t = bySpell[cast.spellID]
        if t and cast.time >= combatStart and cast.time <= combatEnd then t.directs = t.directs + 1 end
    end
    return bySpell
end

local function readableTable(v)
    if issecret(v) or type(v) ~= "table" then return false end
    if type(canaccesstable) ~= "function" then return true end
    local ok, allowed = pcall(canaccesstable, v)
    return ok and allowed == true
end

local loggedFields = false

-- { [spellID] = total healing } for the fight that just ended, or nil plus why.
local function meterNow()
    local DM = C_DamageMeter
    if type(DM) ~= "table" or type(DM.GetCombatSessionSourceFromType) ~= "function" then return nil, "no damage meter" end
    if type(DM.IsDamageMeterAvailable) == "function" then
        local ok, available = pcall(DM.IsDamageMeterAvailable)
        if ok and available == false then return nil, "switched off" end
    end
    local types = Enum and Enum.DamageMeterType
    local healType = types and types.HealingDone
    if healType == nil then return nil, "no healing meter type" end
    local current = Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, totals, why = pcall(function()
        local src = DM.GetCombatSessionSourceFromType(current, healType, UnitGUID("player"))
        if not readableTable(src) or not readableTable(src.combatSpells) then return nil, "wait" end
        local list = src.combatSpells
        local n = #list
        if issecret(n) or type(n) ~= "number" or n == 0 then return nil, "wait" end
        local out = {}
        for i = 1, n do
            local sp = list[i]
            if readableTable(sp) then
                if issecret(sp.totalAmount) or issecret(sp.spellID) then return nil, "wait" end
                if not loggedFields and ns.db.debug then
                    loggedFields = true
                    local keys = {}
                    for key in pairs(sp) do keys[#keys + 1] = tostring(key) end
                    trace("meter row fields: " .. table.concat(keys, ", "))
                end
                if type(sp.totalAmount) == "number" then out[sp.spellID] = sp.totalAmount end
            end
        end
        return out
    end)
    if not ok then return nil, "unreadable" end
    return totals, why
end

local function learn(bySpell, totals, combatStart)
    local db = ns.db
    for spellID, t in pairs(bySpell) do
        local info, name = t.info, t.info.name
        local total = totals[spellID]
        local untrackedAt = ns.untracked[spellID]
        local descTick = info.amount / info.ticks
        local skip
        if t.factors < MIN_FACTORS then
            skip = ("only %d tick(s) counted"):format(t.ticks)
        elseif untrackedAt and untrackedAt >= combatStart - 30 then
            skip = "a cast went to someone outside the group"
        elseif not total then
            skip = "no readable meter total"
        end
        if skip then
            trace(("LEARN %s skipped: %s"):format(name, skip))
        else
            local expected = info.direct * t.directs + descTick * t.factors
            local ratio = total / expected
            if ratio < RATIO_MIN or ratio > RATIO_MAX then
                trace(("LEARN %s skipped: meter %d over %d tick(s) is %.2fx the tooltip%s"):format(name, math.floor(total + 0.5),
                    t.ticks, ratio, ratio < RATIO_MIN and " (overhealing or a dispel)" or ""))
            else
                local tick = ratio * descTick
                local old = db.learned[spellID]
                local weight = old and math.min(old.weight or 0, WEIGHT_CAP) or 0
                local blended = ((old and old.tick or 0) * weight + tick * t.factors) / (weight + t.factors)
                db.learned[spellID] = {
                    tick = math.floor(blended * 10 + 0.5) / 10, weight = weight + t.factors, name = name,
                    desc = descTick,
                }
                trace(("LEARN %s: meter %d over %d tick(s) = %.1f per tick (tooltip %.1f), saved %.1f"):format(
                    name, math.floor(total + 0.5), t.ticks, tick, descTick, db.learned[spellID].tick))
            end
        end
    end
    if ns.onLearned then ns.onLearned() end
end

local function attempt(bySpell, combatStart, triesLeft)
    if ns.inCombat() then
        trace("LEARN skipped: a new fight started before the meter could be read")
        return
    end
    local totals, why = meterNow()
    if not totals and why == "wait" and triesLeft > 0 then
        C_Timer.After(RETRY_SECONDS, function() attempt(bySpell, combatStart, triesLeft - 1) end)
        return
    end
    if not totals then
        trace("LEARN skipped: damage meter " .. (why == "wait" and "still empty or hidden" or tostring(why)))
        return
    end
    learn(bySpell, totals, combatStart)
    ns.pruneLogs()
end

function ns.learnAfterCombat(combatStart, combatEnd)
    if not ns.db.learnFromMeter then ns.pruneLogs() return end
    local bySpell = tally(combatStart, combatEnd)
    if not next(bySpell) then ns.pruneLogs() return end
    C_Timer.After(RETRY_SECONDS, function() attempt(bySpell, combatStart, TRIES) end)
end

function ns.forgetLearned()
    wipe(ns.db.learned)
    if ns.onLearned then ns.onLearned() end
end
