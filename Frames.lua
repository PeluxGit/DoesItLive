local _, ns = ...

-- Finds health bars in supported frame addons and puts a HoT block (Display.lua) on each:
--   EllesmereUI raid, party, player, target and focus frames; Blizzard's compact party/raid frames, default
--   party frames, player, target and focus frames (BetterBlizzFrames' bars when it's on); ElvUI and other oUF
--   layouts. Friendly nameplates are in Nameplates.lua.

local issecret = issecretvalue or function() return false end

ns.overlays = {}   -- [healthBar] = { block, getUnit, source, serial }
ns.testMode = false

local SINGLE_UNITS = { player = true, target = true, focus = true }

-- Units a block can be drawn for: you, your target and focus, group members and friendly nameplates.
local function isShownUnit(unit)
    return type(unit) == "string" and not issecret(unit)
        and (SINGLE_UNITS[unit] or unit:find("^party%d") or unit:find("^raid%d") or unit:find("^nameplate%d"))
        and true or false
end

local function fillsLeftToRight(bar)
    local okO, orient = pcall(bar.GetOrientation, bar)
    local okR, reverse = pcall(bar.GetReverseFill, bar)
    return (not okO or orient ~= "VERTICAL") and (not okR or not reverse)
end

local skipped = setmetatable({}, { __mode = "k" }) -- bars already reported as not fillable, so it's said once

function ns.track(bar, getUnit, source)
    local o = ns.overlays[bar]
    if o then o.getUnit, o.source = getUnit, source return end
    if not fillsLeftToRight(bar) then
        if not skipped[bar] then
            skipped[bar] = true
            ns.trace(source .. ": skipped a bar that doesn't fill left to right")
        end
        return
    end
    ns.overlays[bar] = { block = ns.createBlock(bar), getUnit = getUnit, source = source, serial = 0 }
end
local track = ns.track

---------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------

-- EllesmereUI raid and party frames: SecureGroupHeader buttons, health bar is a StatusBar child
-- (EllesmereUIRaidFrames/EUI_RaidFrames_Style.lua). The tallest StatusBar child is the health bar
-- (the other one is the power bar).
local EUI_HEADERS = { "ERFFlatHeader", "ERFPartyHeader" }
for i = 1, 8 do EUI_HEADERS[#EUI_HEADERS + 1] = "ERFGroupHeader" .. i end

local function euiHealthBar(button)
    local best, bestH
    for _, child in ipairs({ button:GetChildren() }) do
        if child:IsObjectType("StatusBar") then
            local h = child:GetHeight()
            if h and (not bestH or h > bestH) then best, bestH = child, h end
        end
    end
    return best
end

local function euiButton(button)
    local bar = euiHealthBar(button)
    if bar then track(bar, function() return button:GetAttribute("unit") end, "EllesmereUI") end
end

local function scanEllesmere()
    for _, name in ipairs(EUI_HEADERS) do
        local header = _G[name]
        if header then
            for _, button in ipairs({ header:GetChildren() }) do
                if button:IsObjectType("Button") then euiButton(button) end
            end
        end
    end
    if _G.ERFPartySelfButton then euiButton(_G.ERFPartySelfButton) end
end

-- EllesmereUI player, target and focus frames (EllesmereUIUnitFrames/EUI_UnitFrames_Init.lua).
local EUI_UNIT_FRAMES = {
    player = "EllesmereUIUnitFrames_Player",
    target = "EllesmereUIUnitFrames_Target",
    focus  = "EllesmereUIUnitFrames_Focus",
}

local function scanEllesmereUnitFrames()
    for unit, name in pairs(EUI_UNIT_FRAMES) do
        local frame = _G[name]
        if frame and frame.Health then
            track(frame.Health, function() return unit end, "EllesmereUI unit frames")
        end
    end
end

-- Blizzard player, target and focus frames (hidden while another addon replaces them, so skipped then).
local BLIZZ_UNIT_FRAMES = { player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame" }

local function blizzUnitHealthBar(frame, unit)
    if frame.healthbar then return frame.healthbar end
    local content = frame[unit == "player" and "PlayerFrameContent" or "TargetFrameContent"]
    local main = content and content[unit == "player" and "PlayerFrameContentMain" or "TargetFrameContentMain"]
    local container = main and main.HealthBarsContainer
    return container and container.HealthBar
end

-- BetterBlizzFrames' bigger health bars are its own bar drawn over Blizzard's (which goes alpha 0, so a block on
-- it would be invisible): BBF.HealthBar gives the bar in use (from DoesItDie's Frames.lua).
local function betterBlizzHealthBar(frame)
    if type(BBF) ~= "table" or type(BBF.HealthBar) ~= "function" then return nil end
    local ok, bar = pcall(BBF.HealthBar, frame)
    if ok and type(bar) == "table" then return bar end
end

local function scanBlizzardUnitFrames()
    for unit, name in pairs(BLIZZ_UNIT_FRAMES) do
        local frame = _G[name]
        if frame then
            local bbf = betterBlizzHealthBar(frame)
            if bbf then track(bbf, function() return unit end, "BetterBlizzFrames") end
            local bar = blizzUnitHealthBar(frame, unit)
            if bar and bar ~= bbf then track(bar, function() return unit end, "Blizzard unit frames") end
        end
    end
end

-- Blizzard's default party frames (when "raid-style party frames" is off): PartyFrame.MemberFrame1-4 on current
-- clients, PartyMemberFrame1-4 on older ones.
local function scanBlizzardPartyFrames()
    for i = 1, 4 do
        local frames = { PartyFrame and PartyFrame["MemberFrame" .. i], _G["PartyMemberFrame" .. i] }
        for _, frame in pairs(frames) do
            local bar = frame.healthbar or frame.HealthBar
                or (frame.HealthBarContainer and frame.HealthBarContainer.HealthBar)
            if bar then
                track(bar, function() return frame.unit or ("party" .. i) end, "Blizzard party frames")
            end
        end
    end
end

-- Blizzard compact party/raid frames.
local blizzFrames = setmetatable({}, { __mode = "k" })
if CompactUnitFrame_SetUnit then
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame) blizzFrames[frame] = true end)
end

local function scanBlizzard()
    -- Frames set up before this addon loaded never went through the hook: pick them up by name.
    for i = 1, 5 do blizzFrames[_G["CompactPartyFrameMember" .. i] or false] = true end
    for i = 1, 40 do blizzFrames[_G["CompactRaidFrame" .. i] or false] = true end
    for g = 1, 8 do
        for m = 1, 5 do blizzFrames[_G["CompactRaidGroup" .. g .. "Member" .. m] or false] = true end
    end
    blizzFrames[false] = nil
    for frame in pairs(blizzFrames) do
        if frame.healthBar and not (frame.unit and tostring(frame.unit):find("^nameplate")) then
            track(frame.healthBar, function() return frame.displayedUnit or frame.unit end, "Blizzard raid frames")
        end
    end
end

-- oUF-based layouts: ElvUI (ElvUF) and plain oUF.
local function scanOUF()
    for _, global in ipairs({ "ElvUF", "oUF" }) do
        local lib = _G[global]
        if type(lib) == "table" and type(lib.objects) == "table" then
            for _, obj in ipairs(lib.objects) do
                if obj.Health and isShownUnit(obj.unit) then
                    track(obj.Health, function() return obj.unit end, global)
                end
            end
        end
    end
end

function ns.rescan()
    if not ns.db then return end
    scanEllesmere()
    scanEllesmereUnitFrames()
    scanBlizzard()
    scanBlizzardUnitFrames()
    scanBlizzardPartyFrames()
    scanOUF()
end

-- A new target or focus can carry your HoTs: redraw right away rather than on the next tick.
local unitEvents = CreateFrame("Frame")
unitEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
unitEvents:RegisterEvent("PLAYER_FOCUS_CHANGED")
unitEvents:SetScript("OnEvent", function() ns.redraw() end)

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function ns.refreshLook()
    for _, o in pairs(ns.overlays) do o.block:ApplyLook() end
    if ns.onLookChanged then ns.onLookChanged() end
    ns.redraw()
end

-- Test mode: a sample block on every frame, a quarter of the bar, split 60/40 between two HoTs.
local TEST_PARTS = { { name = "Regrowth", amount = 0.10 }, { name = "Rejuvenation", amount = 0.15 } }

function ns.redraw()
    if not ns.db then return end
    for bar, o in pairs(ns.overlays) do
        local unit = o.getUnit()
        local show = ns.db.enabled and isShownUnit(unit) and UnitExists(unit) and ns.barShown(bar)
            and (not unit:find("^nameplate") or ns.db.nameplates)
        if show and ns.testMode then
            o.block:Set(1, 0, 0.25, TEST_PARTS)
        elseif show then
            local total, parts, serial = ns.remainingFor(unit)
            if total > 0 then
                local incoming = ns.db.afterIncoming and UnitGetIncomingHeals and UnitGetIncomingHeals(unit) or 0
                o.block:Set(UnitHealthMax(unit), incoming, total, parts)
                if serial > o.serial then o.block:Spark() end
                o.serial = serial
            else
                o.block:Hide()
                o.serial = 0
            end
        else
            o.block:Hide()
        end
    end
end

-- A new HoT on someone: flash their block(s).
function ns.onApplied(key)
    ns.redraw()
    for _, o in pairs(ns.overlays) do
        local unit = o.getUnit()
        if isShownUnit(unit) and ns.unitKey(unit) == key and o.block:IsShown() then o.block:Flash() end
    end
end

C_Timer.After(0, function()
    C_Timer.NewTicker(ns.RESCAN, ns.rescan)
end)
