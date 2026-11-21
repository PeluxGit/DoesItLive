local addonName, ns = ...

-- DoesItLive options window (/dil).
--
-- Left: a live preview, a mock raid frame carrying a real HoT block (Display.lua) fed plain numbers.
-- Right: tabbed settings. Top: presets.
-- Window, controls and presets follow DoesItDie's options window by Joe Greive (MIT, see
-- LICENSE-DoesItDie.txt): basic widgets (CheckButton, Slider, Button) rather than Blizzard templates, so
-- they don't depend on templates behaving the same in Forever. Settings are written straight to ns.db.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WINDOW_WIDTH, WINDOW_HEIGHT = 720, 470
local HEADER_HEIGHT = 52
local PREVIEW_WIDTH = 230
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 170, control = 200 }
local DISABLED_ALPHA = 0.35

local window
local controls = {}
local tabs, activeTab = {}, nil
local menu

local preview = { health = 55, incoming = 8, parts = {
    { name = "Regrowth", amount = 12 }, { name = "Rejuvenation", amount = 18 },
} }

local function db() return ns.db end

local function findEntry(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry end
    end
end

local function setBackdrop(frame, shade, alpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(shade, shade, shade, alpha or 1)
    frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

local function say(msg) print("|cff40d090DoesItLive|r " .. msg) end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------

local function updatePreview()
    if not window or not window.previewBlock then return end
    window.mockHealth:SetValue(preview.health)
    local total = 0
    for _, part in ipairs(preview.parts) do total = total + part.amount end
    window.previewBlock:Set(100, db().afterIncoming and preview.incoming or 0, total, preview.parts)
    window.mockIncoming:SetValue(db().afterIncoming and preview.incoming or 0)
end

local function refreshControls()
    for _, control in ipairs(controls) do control:Refresh() end
end

local function changed()
    ns.refreshLook()
    refreshControls()
    updatePreview()
end

function ns.onLookChanged()
    if window and window.previewBlock then window.previewBlock:ApplyLook() updatePreview() end
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function makeRow(parent, labelText, opts)
    local layout = opts.layout or SETTINGS_LAYOUT
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(layout.label + layout.control + 50, ROW_HEIGHT)
    row.layout = layout
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetWidth(layout.label - 8)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(labelText)
    row.enabledIf = opts.enabledIf
    if opts.tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(opts.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function row:ApplyEnabled(widget)
        local enabled = not self.enabledIf or self.enabledIf(db())
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        widget:EnableMouse(enabled)
        if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
    end
    table.insert(controls, row)
    return row
end

local function checkbox(parent, key, labelText, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local box = CreateFrame("CheckButton", nil, row)
    box:SetSize(24, 24)
    box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box:SetScript("OnClick", function(self)
        db()[key] = self:GetChecked() and true or false
        changed()
    end)
    function row:Refresh()
        box:SetChecked(db()[key] and true or false)
        self:ApplyEnabled(box)
    end
    return row
end

local function sliderRow(parent, labelText, min, max, step, get, set, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(row.layout.control - 44, 18)
    slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local trackTex = slider:CreateTexture(nil, "BACKGROUND")
    trackTex:SetColorTexture(0.3, 0.3, 0.32, 1)
    trackTex:SetHeight(4)
    trackTex:SetPoint("LEFT")
    trackTex:SetPoint("RIGHT")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(18, 24)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    local suffix = opts.suffix or ""
    local updating = false
    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(value .. suffix)
        set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    function row:Refresh()
        updating = true
        local value = get()
        slider:SetValue(value)
        valueText:SetText(math.floor(value / step + 0.5) * step .. suffix)
        updating = false
        self:ApplyEnabled(slider)
    end
    return row
end

local function slider(parent, key, labelText, min, max, step, opts)
    return sliderRow(parent, labelText, min, max, step,
        function() return db()[key] end,
        function(value) db()[key] = value changed() end, opts)
end

local function closeMenu()
    if menu then menu:Hide() end
end

local function openMenu(owner, list, current, pick)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:EnableMouse(true)
        setBackdrop(menu, 0.08, 0.98)
        menu.buttons = {}
        pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
        end)
    end
    if menu:IsShown() and menu.owner == owner then return menu:Hide() end
    menu.owner = owner
    for i, entry in ipairs(list) do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(20)
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.1)
            button.swatch = button:CreateTexture(nil, "ARTWORK")
            button.swatch:SetSize(12, 12)
            button.swatch:SetPoint("LEFT", 8, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetJustifyH("LEFT")
            menu.buttons[i] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 20)
        button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
        button.swatch:SetShown(entry.rgb ~= nil)
        if entry.rgb then button.swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", entry.rgb and 26 or 8, 0)
        button.text:SetText(entry.id == current and ("|cffffd100" .. entry.label .. "|r") or entry.label)
        button:SetScript("OnClick", function()
            menu:Hide()
            pick(entry.id)
        end)
        button:Show()
    end
    for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(owner:GetWidth(), #list * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function choice(parent, key, labelText, list, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetSize(row.layout.control, 22)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    setBackdrop(button, 0.13)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(12, 12)
    swatch:SetPoint("LEFT", 8, 0)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    button:SetScript("OnClick", function(self)
        openMenu(self, list, db()[key], function(id)
            db()[key] = id
            changed()
        end)
    end)
    function row:Refresh()
        local entry = findEntry(list, db()[key])
        text:SetText(entry and entry.label or tostring(db()[key]))
        swatch:SetShown(entry ~= nil and entry.rgb ~= nil)
        if entry and entry.rgb then swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        text:ClearAllPoints()
        text:SetPoint("LEFT", (entry and entry.rgb) and 26 or 8, 0)
        text:SetPoint("RIGHT", -20, 0)
        self:ApplyEnabled(button)
    end
    return row
end

local function pushButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function actionRow(parent, labelText, buttonText, onClick, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = pushButton(row, buttonText, row.layout.control, onClick)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    function row:Refresh() self:ApplyEnabled(button) end
    return row
end

-- A block of text that fills the rest of the tab (the learned sizes list).
local function textBlock(parent, getText, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(SETTINGS_LAYOUT.label + SETTINGS_LAYOUT.control + 50, height)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 6, -2)
    text:SetPoint("RIGHT", -6, 0)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    function row:Refresh() text:SetText(getText()) end
    table.insert(controls, row)
    return row
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function selectTab(tab)
    closeMenu()
    activeTab = tab
    for _, other in ipairs(tabs) do
        local selected = other == tab
        other.content:SetShown(selected)
        other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
        other.button.underline:SetShown(selected)
    end
end

local function addTab(name)
    local area = window.settingsArea
    local tab = { keys = {}, y = 0 }
    tab.content = CreateFrame("Frame", nil, area)
    tab.content:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -40)
    tab.content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 40)
    tab.content:Hide()

    local button = CreateFrame("Button", nil, area)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetText(name)
    button:SetSize(button.text:GetStringWidth() + 16, 26)
    button.text:SetPoint("CENTER")
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetColorTexture(1, 0.82, 0, 1)
    button.underline:SetHeight(2)
    button.underline:SetPoint("BOTTOMLEFT", 3, 0)
    button.underline:SetPoint("BOTTOMRIGHT", -3, 0)
    local previous = tabs[#tabs]
    if previous then
        button:SetPoint("LEFT", previous.button, "RIGHT", 4, 0)
    else
        button:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
    end
    button:SetScript("OnClick", function() selectTab(tab) end)
    tab.button = button

    local function place(row, key)
        row:SetPoint("TOPLEFT", tab.content, "TOPLEFT", 0, -tab.y)
        tab.y = tab.y + (row:GetHeight() > ROW_HEIGHT and row:GetHeight() or ROW_HEIGHT)
        if key then table.insert(tab.keys, key) end
        return row
    end
    function tab:checkbox(key, ...) return place(checkbox(self.content, key, ...), key) end
    function tab:slider(key, ...) return place(slider(self.content, key, ...), key) end
    function tab:choice(key, ...) return place(choice(self.content, key, ...), key) end
    function tab:action(...) return place(actionRow(self.content, ...)) end
    function tab:text(...) return place(textBlock(self.content, ...)) end
    function tab:gap() self.y = self.y + 8 end

    table.insert(tabs, tab)
    return tab
end

local function resetTab(tab)
    for _, key in ipairs(tab.keys) do db()[key] = ns.DEFAULTS[key] end
    changed()
end

local function applyPreset(preset)
    for key, value in pairs(preset.values) do db()[key] = value end
    changed()
    say(preset.label .. " preset applied.")
end

local function learnedText()
    local lines = {}
    for spellID, l in pairs(db().learned) do
        lines[#lines + 1] = ("%s (%d): |cffffffff%.1f|r per tick, tooltip %.1f, from %d ticks"):format(
            l.name or "?", spellID, l.tick or 0, l.desc or 0, math.floor((l.weight or 0) + 0.5))
    end
    table.sort(lines)
    if #lines == 0 then
        return "Nothing learned yet. After each fight with your HoTs, the damage meter's healing totals teach "
            .. "the real tick sizes (turn debug on to see each step)."
    end
    return "Learned from the damage meter:\n" .. table.concat(lines, "\n")
end

local function hasOutline(s) return s.outlineStyle ~= "none" end
local function isDashed(s) return s.outlineStyle == "dashed" end
local function singleColor(s) return s.hotColors == "single" end
local function perHot(s) return s.hotColors ~= "single" end
local function showsLabel(s) return s.showLabel end

local function buildTabs()
    local block = addTab("Block")
    block:checkbox("enabled", "Show HoT blocks")
    block:checkbox("nameplates", "On friendly nameplates", {
        tooltip = "Blizzard's, EllesmereUI's, Platynator's, Threat Plates' and other nameplate addons' health bars. "
            .. "Friendly nameplates are off limits to addons in instances." })
    block:choice("fillTexture", "Fill style", ns.FILL_STYLES)
    block:choice("hotColors", "Colors", ns.HOT_COLOR_MODES, {
        tooltip = "By spell: Rejuvenation green, Regrowth teal, Wild Growth lime, Renew gold, Riptide blue." })
    block:choice("fillColor", "Fill color", ns.COLOR_PRESETS, { enabledIf = singleColor })
    block:slider("fillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%" })
    block:checkbox("segmentDividers", "Lines between HoTs", { enabledIf = perHot })
    block:choice("drain", "As ticks land", ns.DRAIN_MODES, {
        tooltip = "Step down: the block shrinks by one tick as each lands. Shrink smoothly: it eats into the next "
            .. "tick as it approaches." })

    local effects = addTab("Outline & effects")
    effects:choice("outlineStyle", "Outline", ns.OUTLINE_STYLES)
    effects:choice("dashLength", "Dash length", ns.DASH_LENGTHS, { enabledIf = isDashed })
    effects:slider("outlineThickness", "Outline thickness", 1, 3, 1, { suffix = "px", enabledIf = hasOutline })
    effects:choice("outlineColor", "Outline color", ns.COLOR_PRESETS)
    effects:slider("outlineOpacity", "Outline opacity", 0, 100, 5, { suffix = "%" })
    effects:checkbox("pulseOutline", "Pulse outline", { enabledIf = hasOutline })
    effects:checkbox("showGlow", "Glow", { tooltip = "A soft halo inside the block, in the outline color." })
    effects:slider("glowSize", "Glow size", 2, 10, 1, { suffix = "px", enabledIf = function(s) return s.showGlow end })
    effects:checkbox("showSpark", "Spark on each tick", { tooltip = "A flare on the block's end as each tick lands." })
    effects:checkbox("flashOnApply", "Flash when you cast")

    local text = addTab("Text")
    text:checkbox("showLabel", "Show healing left", { tooltip = "The healing your HoTs still have to do, as a number." })
    text:choice("labelPosition", "Position", ns.LABEL_POSITIONS, { enabledIf = showsLabel })
    text:slider("labelSize", "Size", 7, 14, 1, { enabledIf = showsLabel })
    text:choice("labelColor", "Color", ns.COLOR_PRESETS, { enabledIf = showsLabel })

    local accuracy = addTab("Accuracy")
    accuracy:checkbox("afterIncoming", "Start after incoming heals", {
        tooltip = "Starts the block where the game's incoming-heal bar ends (EllesmereUI's green bar), so the two "
            .. "don't overlap." })
    accuracy:slider("scale", "Scale estimates", 50, 200, 5, { suffix = "%",
        tooltip = "Multiplies every estimate. Applies to new casts." })
    accuracy:checkbox("learnFromMeter", "Learn from the damage meter", {
        tooltip = "After each fight, compares your HoTs' healing on the damage meter with the ticks counted, and "
            .. "saves the real tick size. Fights with overhealing are skipped." })
    accuracy:checkbox("useBonusHealing", "Add +healing until learned", {
        tooltip = "Tooltips leave out +healing. Until a spell is learned, adds +healing x a rough coefficient." })
    accuracy:gap()
    accuracy:text(learnedText, 120)
    accuracy:action("", "Forget learned sizes", function() ns.forgetLearned() refreshControls() end)

    local general = addTab("General")
    general:checkbox("debug", "Debug messages", { tooltip = "Prints each cast, parse and learning step in chat." })
    general:action("Test on your frames", "Toggle test blocks", function() SlashCmdList.DOESITLIVE("test") end)
    general:action("What the game allows", "Run probe", function() SlashCmdList.DOESITLIVE("probe") end)
end

local function buildPreview(pane)
    local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Preview")

    -- A mock raid frame: dark background, class-colored health, the game's incoming heal, and the block.
    local mock = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    mock:SetSize(150, 46)
    mock:SetPoint("TOP", pane, "TOP", 0, -50)
    setBackdrop(mock, 0.1)
    local health = CreateFrame("StatusBar", nil, mock)
    health:SetPoint("TOPLEFT", 1, -1)
    health:SetPoint("BOTTOMRIGHT", -1, 1)
    health:SetStatusBarTexture(WHITE)
    health:SetStatusBarColor(1, 0.49, 0.04) -- druid orange
    health:SetMinMaxValues(0, 100)
    local name = health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", 6, 0)
    name:SetText("Daft")
    -- Stand-in for the frame addon's own incoming-heal bar.
    local incoming = CreateFrame("StatusBar", nil, health)
    incoming:SetStatusBarTexture(WHITE)
    incoming:SetStatusBarColor(0.4, 0.95, 0.4, 0.4)
    incoming:SetPoint("TOPLEFT", health:GetStatusBarTexture(), "TOPRIGHT")
    incoming:SetPoint("BOTTOMLEFT", health:GetStatusBarTexture(), "BOTTOMRIGHT")
    incoming:SetWidth(148)
    incoming:SetMinMaxValues(0, 100)
    incoming:SetFrameLevel(health:GetFrameLevel() + 3)
    window.mockHealth, window.mockIncoming = health, incoming
    window.previewBlock = ns.createBlock(health)

    local note = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOP", mock, "BOTTOM", 0, -8)
    note:SetWidth(PREVIEW_WIDTH - 24)
    note:SetText("Pale green: the game's incoming heal. After it: your HoTs.")

    local layout = { label = 70, control = 140 }
    local healthRow = sliderRow(pane, "Health", 0, 100, 5,
        function() return preview.health end,
        function(v) preview.health = v updatePreview() end, { layout = layout, suffix = "%" })
    healthRow:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -150)
    local hotRow = sliderRow(pane, "HoTs", 0, 100, 5,
        function() return preview.parts[1].amount + preview.parts[2].amount end,
        function(v)
            preview.parts[1].amount, preview.parts[2].amount = v * 0.4, v * 0.6
            updatePreview()
        end, { layout = layout, suffix = "%" })
    hotRow:SetPoint("TOPLEFT", healthRow, "BOTTOMLEFT", 0, -4)

    local flash = pushButton(pane, "Flash", 96, function()
        window.previewBlock.flashAnim:Stop() window.previewBlock.flashAnim:Play()
    end)
    flash:SetPoint("TOPLEFT", hotRow, "BOTTOMLEFT", 8, -12)
    local tick = pushButton(pane, "Tick", 96, function()
        window.previewBlock.sparkAnim:Stop() window.previewBlock.sparkAnim:Play()
    end)
    tick:SetPoint("LEFT", flash, "RIGHT", 8, 0)
end

local function createWindow()
    window = CreateFrame("Frame", "DoesItLiveOptions", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    setBackdrop(window, 0.06, 0.97)
    table.insert(UISpecialFrames, "DoesItLiveOptions")

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -18)
    title:SetText("DoesItLive")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -12)

    local previous
    for i = #ns.PRESETS, 1, -1 do
        local preset = ns.PRESETS[i]
        local button = pushButton(window, preset.label, 72, function() applyPreset(preset) end)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("RIGHT", close, "LEFT", -8, 0)
        end
        previous = button
    end
    local presetLabel = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    presetLabel:SetPoint("RIGHT", previous, "LEFT", -8, 0)
    presetLabel:SetText("Presets")

    local pane = CreateFrame("Frame", nil, window, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 10, -HEADER_HEIGHT)
    pane:SetPoint("BOTTOMLEFT", 10, 10)
    pane:SetWidth(PREVIEW_WIDTH)
    setBackdrop(pane, 0.09)

    local area = CreateFrame("Frame", nil, window, "BackdropTemplate")
    area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
    area:SetPoint("BOTTOMRIGHT", -10, 10)
    setBackdrop(area, 0.09)
    window.settingsArea = area

    local divider = area:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.28, 0.28, 0.3, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", -8, -34)

    buildPreview(pane)
    buildTabs()
    local reset = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)

    window:SetScript("OnShow", function()
        refreshControls()
        window.previewBlock:ApplyLook()
        updatePreview()
    end)
    window:SetScript("OnHide", closeMenu)
    selectTab(tabs[1])
end

function ns.openOptions()
    if not ns.db then return end
    if not window then createWindow() end
    window:SetShown(not window:IsShown())
end

function ns.onLearned()
    if window and window:IsShown() then refreshControls() end
end

-- Options > AddOns > DoesItLive: a short page with a button that opens the window.
function ns.registerOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DoesItLive")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetText("Settings have their own window with a live preview. You can also type /dil.")
    local open = pushButton(panel, "Open DoesItLive options", 200, function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        if not (window and window:IsShown()) then ns.openOptions() end
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "DoesItLive")
    Settings.RegisterAddOnCategory(category)
end
