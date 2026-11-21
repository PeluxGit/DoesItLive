local _, ns = ...

-- HoT blocks on friendly nameplates. Finding a plate's health bar is ported from DoesItDie's Nameplates.lua
-- (Joe Greive, MIT, see LICENSE-DoesItDie.txt), which supports, in order:
--   EllesmereUI (its own pooled plate, bar at .health), Platynator (display frames reassigned between units),
--   Threat Plates (plate.TPFrame.visual.Healthbar), Blizzard's own bar, then an automatic search for other plate
--   addons (Plater, KUI, ...) that keep a StatusBar under a field named like "health".
-- Blocks are parented to the bar itself; each bar remembers which unit it's showing (barUnit), updated as plates
-- come and go, so reassigned bars (Platynator) follow their unit.

local issecret = issecretvalue or function() return false end

local function isStatusBar(value)
    if type(value) ~= "table" or type(value.GetObjectType) ~= "function" then return false end
    local ok, kind = pcall(value.GetObjectType, value)
    return ok and kind == "StatusBar"
end

local function forbidden(frame)
    local ok, result = pcall(function() return frame.IsForbidden and frame:IsForbidden() end)
    return not ok or result == true
end

-- False only when the bar is known to be hidden or fully transparent.
local function barShown(bar)
    local ok, visible = pcall(bar.IsVisible, bar)
    if ok and not issecret(visible) and visible == false then return false end
    local okAlpha, alpha = pcall(bar.GetEffectiveAlpha, bar)
    if okAlpha and type(alpha) == "number" and not issecret(alpha) and alpha <= 0 then return false end
    return true
end
ns.barShown = barShown

-- Platynator: preallocated display frames parented to UIParent or the plate; the one showing a unit has
-- .unit = the plate token and a health widget with the StatusBar in .statusBar.
local platyDisplays = {}
local platyLastScan = -math.huge

local function isPlatyDisplay(frame)
    return type(frame.widgets) == "table" and type(frame.Install) == "function" and type(frame.SetUnit) == "function"
end

local function scanPlatyDisplays(plate)
    for _, parent in ipairs({ UIParent, plate }) do
        for _, child in ipairs({ parent:GetChildren() }) do
            if not platyDisplays[child] and isPlatyDisplay(child) then platyDisplays[child] = true end
        end
    end
end

local function platyBarFor(unit)
    for display in pairs(platyDisplays) do
        if display.unit == unit and display:IsShown() and type(display.widgets) == "table" then
            for _, widget in ipairs(display.widgets) do
                if type(widget.details) == "table" and widget.details.kind == "health" and widget.statusBar then
                    return widget.statusBar
                end
            end
        end
    end
end

local function findPlatynatorBar(plate, unit)
    if not (Platynator and unit) then return nil end
    local bar = platyBarFor(unit)
    if bar then return bar end
    local now = GetTime()
    if now - platyLastScan < 2 then return nil end
    platyLastScan = now
    scanPlatyDisplays(plate)
    return platyBarFor(unit)
end

-- Automatic search (Plater, KUI, ...): breadth-first through the plate's frames and plain tables, the first
-- shown StatusBar under a key containing "health" that sits inside the plate.
local SEARCH_DEPTH = 4
local MAX_TABLE_ENTRIES = 200

local function isUnder(frame, plate)
    local current = frame
    for _ = 1, 12 do
        local ok, parent = pcall(current.GetParent, current)
        if not ok or parent == nil then return false end
        if parent == plate then return true end
        current = parent
    end
    return false
end

local function isFrame(value)
    local ok, kind = pcall(function() return value:GetObjectType() end)
    return ok and type(kind) == "string"
end

local function tableFields(container, plain)
    local ok, fields = pcall(function()
        local found, count = {}, 0
        for key, value in pairs(container) do
            count = count + 1
            if plain and count > MAX_TABLE_ENTRIES then return nil end
            if type(key) == "string" and type(value) == "table" then table.insert(found, { key, value }) end
        end
        return found
    end)
    if not ok or not fields then return nil end
    table.sort(fields, function(a, b) return a[1] < b[1] end)
    return fields
end

local function searchHealthBar(plate)
    local blizzardBar = plate.UnitFrame and plate.UnitFrame.healthBar
    local queue = { { node = plate, depth = 0, plain = false } }
    local seen = { [plate] = true }
    local head = 1
    while queue[head] do
        local item = queue[head]
        head = head + 1
        local fields = tableFields(item.node, item.plain)
        if fields then
            for _, field in ipairs(fields) do
                local key, value = field[1], field[2]
                local ok, found = pcall(function()
                    return key:lower():find("health", 1, true) and value ~= blizzardBar and isStatusBar(value)
                        and not forbidden(value) and isUnder(value, plate) and barShown(value)
                end)
                if ok and found then return value end
            end
            if item.depth < SEARCH_DEPTH then
                for _, field in ipairs(fields) do
                    local value = field[2]
                    if not seen[value] and value ~= plate.UnitFrame then
                        seen[value] = true
                        local frame = isFrame(value)
                        local ok, visit = pcall(function()
                            if frame then return not isStatusBar(value) and not forbidden(value) and isUnder(value, plate) end
                            return true
                        end)
                        if ok and visit then
                            table.insert(queue, { node = value, depth = item.depth + 1, plain = not frame })
                        end
                    end
                end
            end
        end
    end
end

local function findThreatPlatesBar(plate)
    local tp = plate.TPFrame
    if type(tp) ~= "table" or not tp.Active or type(tp.visual) ~= "table" then return nil end
    local bar = tp.visual.Healthbar or tp.visual.healthbar
    if isStatusBar(bar) and not forbidden(bar) and barShown(bar) then return bar end
end

-- The health bar a friendly nameplate shows and who draws it, or nil.
local function findPlateBar(plate, unit)
    local eui = EllesmereNameplates_NS
    local euiPlate = type(eui) == "table" and type(eui.plates) == "table" and eui.plates[unit]
    if type(euiPlate) == "table" and euiPlate.nameplate == plate and isStatusBar(euiPlate.health) then
        return euiPlate.health, "EllesmereUI nameplates"
    end
    local ok, platyBar = pcall(findPlatynatorBar, plate, unit)
    if ok and platyBar then return platyBar, "Platynator" end
    local tpOk, tpBar = pcall(findThreatPlatesBar, plate)
    if tpOk and tpBar then return tpBar, "Threat Plates" end
    local unitFrame = plate.UnitFrame
    local blizzard = unitFrame and (unitFrame.healthBar
        or (unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar) or unitFrame.HealthBar)
    if blizzard and barShown(blizzard) then return blizzard, "Blizzard nameplates" end
    local searchOk, found = pcall(searchHealthBar, plate)
    if searchOk and found then return found, "nameplate addon (auto)" end
end

---------------------------------------------------------------------------
-- Plate events
---------------------------------------------------------------------------

local barUnit = {} -- [healthBar] = nameplate unit token it shows now

local function friendlyUnit(unit)
    local ok, isFriend = pcall(UnitIsFriend, "player", unit)
    return ok and not issecret(isFriend) and isFriend
end

local function attach(unit, retry)
    if not ns.db or not ns.db.nameplates then return end
    if not friendlyUnit(unit) then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or forbidden(plate) then return end -- friendly plates are forbidden to addons in instances
    local bar, source = findPlateBar(plate, unit)
    if not bar then
        -- Some plate addons draw a frame after the event: look once more on the next frame.
        if not retry then C_Timer.After(0, function() attach(unit, true) end) end
        return
    end
    barUnit[bar] = unit
    ns.track(bar, function() return barUnit[bar] end, source)
    ns.redraw()
end

local function detach(unit)
    for bar, u in pairs(barUnit) do
        if u == unit then barUnit[bar] = nil end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, unit)
    if issecret(unit) then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        detach(unit)
        attach(unit)
    else
        detach(unit)
    end
end)
