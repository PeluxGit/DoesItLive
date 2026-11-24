local addonName, ns = ...

-- The HoT block drawn on one health bar.
--
-- Geometry, all without math on secret values (StatusBars accept them):
--   inc    starts at the health fill's right edge, filled to the game's incoming heals, invisible;
--   total  starts at inc's fill end (or the health edge), filled to the remaining HoT healing, invisible:
--          its fill texture is the "span" every visible layer is drawn on;
--   segment i is a StatusBar sharing total's start and scale, filled to the running total of HoTs 1..i,
--          drawn from segment i-1's fill end to its own.
-- A clip frame on the health bar cuts off whatever runs past full health.
-- Textures and the drawing approach are from DoesItDie by Joe Greive (MIT, see LICENSE-DoesItDie.txt).

local issecret = issecretvalue or function() return false end
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXTURE_DIR = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
local MAX_SEGMENTS = 5

local FILL_PATHS = {
    flat     = { path = WHITE },
    smooth   = { path = "Interface\\TargetingFrame\\UI-StatusBar" },
    raid     = { path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    stripes  = { path = TEXTURE_DIR .. "Stripes", tiled = true },
    gradient = { path = WHITE, gradient = true },
    none     = {},
}

local COLOR_BY_ID = {}
for _, preset in ipairs(ns.COLOR_PRESETS) do COLOR_BY_ID[preset.id] = preset.rgb end

local function colorOf(id, opacityPercent)
    local rgb = COLOR_BY_ID[id] or COLOR_BY_ID.white
    return rgb[1], rgb[2], rgb[3], (opacityPercent or 100) / 100
end
ns.colorOf = colorOf

local paletteIndexByName, nextPaletteIndex = {}, 1
local function hotColor(name)
    local db = ns.db
    if db.hotColors == "spell" then
        local spell = ns.SPELLS[name]
        if spell and spell.color then return spell.color end
    end
    local index = paletteIndexByName[name]
    if not index then
        index = (nextPaletteIndex - 1) % #ns.HOT_PALETTE + 1
        paletteIndexByName[name], nextPaletteIndex = index, nextPaletteIndex + 1
    end
    return ns.HOT_PALETTE[index]
end

local function invisibleBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    return bar
end

local function scaleStep(group, fromX, fromY, toX, toY, duration, order)
    local anim = group:CreateAnimation("Scale")
    if anim.SetScaleFrom then
        anim:SetScaleFrom(fromX, fromY)
        anim:SetScaleTo(toX, toY)
    else
        anim:SetScale(toX / fromX, toY / fromY)
    end
    anim:SetDuration(duration)
    anim:SetOrder(order)
    return anim
end

local Block = {}
Block.__index = Block

function ns.createBlock(bar)
    local b = setmetatable({ bar = bar }, Block)

    b.clip = CreateFrame("Frame", nil, bar)
    b.clip:SetAllPoints(bar)
    b.clip:SetClipsChildren(true)
    b.clip:SetFrameLevel(bar:GetFrameLevel() + 5) -- above EUI's heal prediction (+3)

    b.inc = invisibleBar(b.clip)
    local fill = bar:GetStatusBarTexture()
    b.inc:SetPoint("TOPLEFT", fill, "TOPRIGHT")
    b.inc:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")

    b.total = invisibleBar(b.clip)
    local span = b.total:GetStatusBarTexture()
    b.span = span

    -- Fill
    b.fillLayer = CreateFrame("Frame", nil, b.total)
    b.fillLayer:SetAllPoints(b.total)
    b.fillTex = b.fillLayer:CreateTexture(nil, "ARTWORK")
    b.fillTex:SetPoint("TOPLEFT", span, "TOPLEFT")
    b.fillTex:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")

    b.segments = {}
    for i = 1, MAX_SEGMENTS do
        local segBar = invisibleBar(b.total)
        segBar:SetAllPoints(b.total)
        local fillEnd = segBar:GetStatusBarTexture()
        local tex = b.fillLayer:CreateTexture(nil, "ARTWORK", nil, 1)
        if i == 1 then
            tex:SetPoint("TOPLEFT", b.total, "TOPLEFT")
        else
            tex:SetPoint("TOPLEFT", b.segments[i - 1].fillEnd, "TOPRIGHT")
        end
        tex:SetPoint("BOTTOMRIGHT", fillEnd, "BOTTOMRIGHT")
        tex:Hide()
        local divider = b.fillLayer:CreateTexture(nil, "OVERLAY", nil, 1)
        divider:SetColorTexture(0, 0, 0, 0.85)
        divider:SetWidth(1)
        divider:SetPoint("TOP", fillEnd, "TOPRIGHT")
        divider:SetPoint("BOTTOM", fillEnd, "BOTTOMRIGHT")
        divider:Hide()
        b.segments[i] = { bar = segBar, fillEnd = fillEnd, texture = tex, divider = divider }
    end

    -- Flash on cast
    b.flashTex = b.fillLayer:CreateTexture(nil, "OVERLAY")
    b.flashTex:SetPoint("TOPLEFT", span, "TOPLEFT")
    b.flashTex:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")
    b.flashTex:SetColorTexture(1, 1, 1, 1)
    b.flashTex:SetBlendMode("ADD")
    b.flashTex:SetAlpha(0)
    b.flashAnim = b.flashTex:CreateAnimationGroup()
    local flashIn = b.flashAnim:CreateAnimation("Alpha")
    flashIn:SetFromAlpha(0) flashIn:SetToAlpha(0.8) flashIn:SetDuration(0.08) flashIn:SetOrder(1)
    local flashOut = b.flashAnim:CreateAnimation("Alpha")
    flashOut:SetFromAlpha(0.8) flashOut:SetToAlpha(0) flashOut:SetDuration(0.5) flashOut:SetSmoothing("OUT")
    flashOut:SetOrder(2)

    -- Outline: dash textures tiled along each edge, so it works whatever the span's length.
    b.outlineLayer = CreateFrame("Frame", nil, b.total)
    b.outlineLayer:SetAllPoints(b.total)
    b.edges = {}
    local function edge(horizontal, p1, p2)
        local tex = b.outlineLayer:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint(p1, span, p1)
        tex:SetPoint(p2, span, p2)
        b.edges[#b.edges + 1] = { texture = tex, horizontal = horizontal }
    end
    edge(true, "TOPLEFT", "TOPRIGHT")
    edge(true, "BOTTOMLEFT", "BOTTOMRIGHT")
    edge(false, "TOPLEFT", "BOTTOMLEFT")
    edge(false, "TOPRIGHT", "BOTTOMRIGHT")
    b.outlinePulse = b.outlineLayer:CreateAnimationGroup()
    b.outlinePulse:SetLooping("BOUNCE")
    local pulse = b.outlinePulse:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1) pulse:SetToAlpha(0.3) pulse:SetDuration(0.9) pulse:SetSmoothing("IN_OUT")

    -- Glow: drawn inside the edges, since the clip frame cuts anything outside.
    b.glows = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local tex = b.outlineLayer:CreateTexture(nil, "BORDER")
        tex:SetTexture(WHITE)
        tex:SetBlendMode("ADD")
        if side == "top" then
            tex:SetPoint("TOPLEFT", span, "TOPLEFT") tex:SetPoint("TOPRIGHT", span, "TOPRIGHT")
        elseif side == "bottom" then
            tex:SetPoint("BOTTOMLEFT", span, "BOTTOMLEFT") tex:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")
        elseif side == "left" then
            tex:SetPoint("TOPLEFT", span, "TOPLEFT") tex:SetPoint("BOTTOMLEFT", span, "BOTTOMLEFT")
        else
            tex:SetPoint("TOPRIGHT", span, "TOPRIGHT") tex:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")
        end
        b.glows[#b.glows + 1] = { texture = tex, side = side }
    end

    -- Spark
    b.sparkLayer = CreateFrame("Frame", nil, b.total)
    b.sparkLayer:SetAllPoints(b.total)
    b.spark = b.sparkLayer:CreateTexture(nil, "OVERLAY")
    b.spark:SetTexture(TEXTURE_DIR .. "Spark")
    b.spark:SetBlendMode("ADD")
    b.spark:SetWidth(10)
    b.spark:SetPoint("TOP", span, "TOPRIGHT", 0, 3)
    b.spark:SetPoint("BOTTOM", span, "BOTTOMRIGHT", 0, -3)
    b.spark:SetAlpha(0)
    b.sparkAnim = b.spark:CreateAnimationGroup()
    local sparkIn = b.sparkAnim:CreateAnimation("Alpha")
    sparkIn:SetFromAlpha(0) sparkIn:SetToAlpha(1) sparkIn:SetDuration(0.06) sparkIn:SetOrder(1)
    scaleStep(b.sparkAnim, 1, 1, 1.8, 1.2, 0.06, 1)
    local sparkOut = b.sparkAnim:CreateAnimation("Alpha")
    sparkOut:SetFromAlpha(1) sparkOut:SetToAlpha(0) sparkOut:SetDuration(0.4) sparkOut:SetSmoothing("OUT")
    sparkOut:SetOrder(2)
    scaleStep(b.sparkAnim, 1.8, 1.2, 1, 1, 0.4, 2)

    -- Text: outside the clip so it can sit anywhere on the bar.
    b.textLayer = CreateFrame("Frame", nil, bar)
    b.textLayer:SetAllPoints(bar)
    b.textLayer:SetFrameLevel(bar:GetFrameLevel() + 7)
    b.label = b.textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

    b:Layout()
    bar:HookScript("OnSizeChanged", function() b:Layout() end)
    b:ApplyLook()
    b:Hide()
    return b
end

-- EllesmereUI's druid player frame: out of Cat Form, a second health bar (health._euiStrip) fills the combo
-- point row above the health bar. The block covers it too.
local function stripHeight(bar)
    local strip = bar._euiStrip
    if type(strip) ~= "table" or type(strip.IsShown) ~= "function" or not strip:IsShown() then return 0 end
    local h = strip:GetHeight()
    if type(h) ~= "number" or issecret(h) or h <= 0 then return 0 end
    return h
end

-- The bar's width can be secret (Blizzard's compact party frames): then it's never compared, only handed to
-- SetWidth, falling back to the last plain width if SetWidth won't take it.
function Block:Layout()
    local up = stripHeight(self.bar)
    self.up = up
    local w = self.bar:GetWidth()
    if w == nil then return end
    if issecret(w) then
        local ok = pcall(self.inc.SetWidth, self.inc, w) and pcall(self.total.SetWidth, self.total, w)
        if not ok and self.width then
            self.inc:SetWidth(self.width)
            self.total:SetWidth(self.width)
        end
    else
        if w <= 0 then return end
        self.width = w
        self.inc:SetWidth(w)
        self.total:SetWidth(w)
    end
    self.clip:ClearAllPoints()
    self.clip:SetPoint("TOPLEFT", self.bar, "TOPLEFT", 0, up)
    self.clip:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT")
    self.total:ClearAllPoints()
    local from = ns.db.afterIncoming and self.inc:GetStatusBarTexture() or self.bar:GetStatusBarTexture()
    self.total:SetPoint("TOPLEFT", from, "TOPRIGHT", 0, up)
    self.total:SetPoint("BOTTOMLEFT", from, "BOTTOMRIGHT")
end

function Block:ApplyLook()
    local db = ns.db
    self.last = {}
    local fill = FILL_PATHS[db.fillTexture] or FILL_PATHS.flat
    local perHot = db.hotColors ~= "single"

    -- Single fill
    local r, g, b, a = colorOf(db.fillColor, db.fillOpacity)
    if fill.path and not perHot then
        self.fillTex:SetTexture(fill.path, fill.tiled and "REPEAT" or nil, fill.tiled and "REPEAT" or nil)
        self.fillTex:SetHorizTile(fill.tiled or false)
        self.fillTex:SetVertTile(fill.tiled or false)
        if fill.gradient and CreateColor then
            self.fillTex:SetVertexColor(1, 1, 1, 1)
            self.fillTex:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, a))
        else
            self.fillTex:SetVertexColor(r, g, b, a)
        end
        self.fillTex:Show()
    else
        self.fillTex:Hide()
    end

    -- Segments
    local segPath = (fill.path and not fill.gradient) and fill.path or WHITE
    for _, seg in ipairs(self.segments) do
        seg.texture:SetTexture(segPath, fill.tiled and "REPEAT" or nil, fill.tiled and "REPEAT" or nil)
        seg.texture:SetHorizTile(fill.tiled or false)
        seg.texture:SetVertTile(fill.tiled or false)
        if not perHot then seg.texture:Hide() seg.divider:Hide() end
    end

    -- Outline
    local or_, og, ob, oa = colorOf(db.outlineColor, db.outlineOpacity)
    for _, e in ipairs(self.edges) do
        local tex = e.texture
        if db.outlineStyle == "dashed" then
            tex:SetTexture(TEXTURE_DIR .. (e.horizontal and "DashH" or "DashV") .. db.dashLength, "REPEAT", "REPEAT")
            tex:SetHorizTile(e.horizontal)
            tex:SetVertTile(not e.horizontal)
        else
            tex:SetTexture(WHITE)
            tex:SetHorizTile(false)
            tex:SetVertTile(false)
        end
        tex:SetVertexColor(or_, og, ob, oa)
        if e.horizontal then tex:SetHeight(db.outlineThickness) else tex:SetWidth(db.outlineThickness) end
        tex:SetShown(db.outlineStyle ~= "none")
    end
    if db.pulseOutline and db.outlineStyle ~= "none" then self.outlinePulse:Play() else self.outlinePulse:Stop() end

    -- Glow
    local inner, outer
    if CreateColor then inner, outer = CreateColor(or_, og, ob, oa * 0.7), CreateColor(or_, og, ob, 0) end
    for _, glow in ipairs(self.glows) do
        local tex = glow.texture
        if not inner then
            tex:SetVertexColor(or_, og, ob, oa * 0.35)
            if glow.side == "top" or glow.side == "bottom" then tex:SetHeight(db.glowSize) else tex:SetWidth(db.glowSize) end
        elseif glow.side == "top" then
            tex:SetHeight(db.glowSize) tex:SetGradient("VERTICAL", outer, inner)
        elseif glow.side == "bottom" then
            tex:SetHeight(db.glowSize) tex:SetGradient("VERTICAL", inner, outer)
        elseif glow.side == "left" then
            tex:SetWidth(db.glowSize) tex:SetGradient("HORIZONTAL", inner, outer)
        else
            tex:SetWidth(db.glowSize) tex:SetGradient("HORIZONTAL", outer, inner)
        end
        tex:SetShown(db.showGlow)
    end

    -- Spark
    self.spark:SetVertexColor(math.min(1, or_ + 0.4), math.min(1, og + 0.4), math.min(1, ob + 0.4), 1)
    self.sparkLayer:SetShown(db.showSpark)

    -- Text
    local font = GameFontNormalSmall:GetFont()
    self.label:SetFont(font, db.labelSize, "OUTLINE")
    self.label:SetTextColor(colorOf(db.labelColor))
    self.label:ClearAllPoints()
    if db.labelPosition == "center" then
        self.label:SetPoint("CENTER", self.bar, "CENTER")
    else
        self.label:SetPoint("RIGHT", self.bar, "RIGHT", -3, 0)
    end

    self:Layout()
end

local function short(n)
    if n >= 10000 then return ("+%.0fk"):format(n / 1000) end
    if n >= 1000 then return ("+%.1fk"):format(n / 1000) end
    return ("+%d"):format(math.floor(n + 0.5))
end

-- max, incoming: may be secret, so they're set every time. total, parts: plain numbers from ns.remainingFor,
-- set only when they change (self.last, cleared by ApplyLook and Hide).
function Block:Set(max, incoming, total, parts)
    local db = ns.db
    local last = self.last
    if stripHeight(self.bar) ~= self.up then self:Layout() end
    self.inc:SetMinMaxValues(0, max)
    self.inc:SetValue(incoming or 0)
    self.total:SetMinMaxValues(0, max)
    if last.total ~= total then
        self.total:SetValue(total)
        last.total = total
    end
    if db.hotColors ~= "single" and parts and #parts > 0 then
        local running = 0
        local _, _, _, alpha = colorOf(db.fillColor, db.fillOpacity)
        last.segments = last.segments or {}
        for i, seg in ipairs(self.segments) do
            local part = parts[i]
            local was = last.segments[i]
            if part then
                running = running + part.amount
                local value = i == MAX_SEGMENTS and total or running
                local divider = db.segmentDividers and parts[i + 1] ~= nil
                seg.bar:SetMinMaxValues(0, max)
                if not was or was.value ~= value then seg.bar:SetValue(value) end
                if not was or was.name ~= part.name then
                    local c = hotColor(part.name)
                    seg.texture:SetVertexColor(c[1], c[2], c[3], alpha)
                    seg.texture:Show()
                end
                if not was or was.divider ~= divider then seg.divider:SetShown(divider) end
                last.segments[i] = { value = value, name = part.name, divider = divider }
            elseif was ~= false then
                seg.texture:Hide()
                seg.divider:Hide()
                last.segments[i] = false
            end
        end
    end
    local text = short(total)
    if last.text ~= text then
        self.label:SetText(text)
        last.text = text
    end
    if last.labelShown ~= db.showLabel then
        self.label:SetShown(db.showLabel)
        last.labelShown = db.showLabel
    end
    if not self.clip:IsShown() then
        self.clip:Show()
    end
end

function Block:Hide()
    self.clip:Hide()
    self.label:Hide()
    self.last = {}
end

function Block:IsShown() return self.clip:IsShown() end

function Block:Flash()
    if ns.db.flashOnApply then self.flashAnim:Stop() self.flashAnim:Play() end
end

function Block:Spark()
    if ns.db.showSpark then self.sparkAnim:Stop() self.sparkAnim:Play() end
end
