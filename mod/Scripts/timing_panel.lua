-- SWGR Telemetry: the in-race timing panel (text only, no traces).
-- Built with UMG widgets created at runtime, the same way as N0M4D's MiniMap. It changes nothing in
-- the game: it only adds a panel on top.
local TimingPanel = {}

local function isValid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end); return ok and result == true
end

-- Styles (the same as the panel workshop's). They only use what UMG draws:
-- a plain background, a thin bar on top, and texts with a colour and a size.
-- Column positions and widths are in pixels; fontSizes: title label, title value, label, value, difference.
local STYLES = {
    current = {
        background = {0.02, 0.03, 0.04}, topBar = nil,
        title = {0.70, 0.75, 0.80}, label = {0.70, 0.75, 0.80}, text = {0.93, 0.95, 0.97}, dim = {0.55, 0.60, 0.66},
        best = {0.72, 0.48, 1.00}, better = {0.30, 0.88, 0.50}, worse = {1.00, 0.78, 0.28}, gain = {0.30, 0.88, 0.50}, loss = {1.00, 0.42, 0.40},
        width = 236, padding = 10, rowHeight = 21, columnX = {10, 96, 170}, columnWidths = {70, 72, 58},
        fontSizes = {titleLabel = 12, titleValue = 15, label = 11, value = 13, difference = 11}},
    sith = {
        background = {0.035, 0.012, 0.012}, topBar = {1.00, 0.17, 0.17},
        title = {1.00, 0.30, 0.28}, label = {0.66, 0.58, 0.56}, text = {0.96, 0.92, 0.91}, dim = {0.47, 0.40, 0.39},
        best = {0.72, 0.52, 1.00}, better = {0.31, 0.82, 0.55}, worse = {1.00, 0.76, 0.31}, gain = {0.31, 0.82, 0.55}, loss = {1.00, 0.54, 0.24},
        width = 236, padding = 10, rowHeight = 21, columnX = {10, 96, 170}, columnWidths = {70, 72, 58},
        fontSizes = {titleLabel = 12, titleValue = 15, label = 11, value = 13, difference = 11}},
}
STYLES.compact = {}
for key, value in pairs(STYLES.sith) do STYLES.compact[key] = value end
STYLES.compact.width, STYLES.compact.padding, STYLES.compact.rowHeight = 214, 8, 19
STYLES.compact.columnX, STYLES.compact.columnWidths = {8, 84, 150}, {66, 64, 56}
STYLES.compact.fontSizes = {titleLabel = 11, titleValue = 14, label = 10, value = 12, difference = 10}
STYLES.compact.isCompact = true

local function toLinearColor(channels) return {R = channels[1], G = channels[2], B = channels[3], A = 1} end
-- Colores elegidos en la app (timing_panel.ini, color_*): #RRGGBB como en la pantalla; el panel usa color lineal
local COLOR_SETTINGS = {background = 'color_background', topBar = 'color_top_bar', title = 'color_title', label = 'color_label',
    text = 'color_text', dim = 'color_dim', best = 'color_best', better = 'color_better', worse = 'color_worse', gain = 'color_gain', loss = 'color_loss'}
local function colorFromHex(text)
    local red, green, blue = tostring(text or ''):match('^#?(%x%x)(%x%x)(%x%x)$')
    if not red then return nil end
    local function linear(hex) return (tonumber(hex, 16) / 255) ^ 2.2 end
    return {linear(red), linear(green), linear(blue)}
end
TimingPanel.COLORS = {}
-- La paleta del estilo, con los colores de la app encima (color_top_bar = none quita la barra de arriba)
local function useStyle(styleName, settings)
    local base = STYLES[styleName] or STYLES.compact
    local style = {}
    for key, value in pairs(base) do style[key] = value end
    for key, value in pairs(settings and settings.colors or {}) do
        if key == 'topBar' and value == 'none' then style.topBar = nil
        else style[key] = colorFromHex(value) or style[key] end
    end
    for _, key in ipairs({'title', 'label', 'text', 'dim', 'best', 'better', 'worse', 'gain', 'loss'}) do TimingPanel.COLORS[key] = toLinearColor(style[key]) end
    return style
end
useStyle('compact')

-- Settings (timing_panel.ini in the mod folder). Keys of the file and of the settings table.
local SETTINGS = {
    {file = 'enabled', key = 'enabled', default = true},
    {file = 'style', key = 'style', default = 'compact'},
    {file = 'x', key = 'x', default = 0.045}, {file = 'y', key = 'y', default = 0.265},
    {file = 'scale', key = 'scale', default = 1.15}, {file = 'opacity', key = 'opacity', default = 0.20},
    {file = 'last_lap', key = 'showLastLap', default = true}, {file = 'best_lap', key = 'showBestLap', default = true},
    {file = 'ideal_lap', key = 'showIdealLap', default = true}, {file = 'event_total', key = 'showEventTotal', default = true},
    {file = 'target', key = 'showTarget', default = true}, {file = 'previous_sectors', key = 'showPreviousSectors', default = true},
    {file = 'compare_with', key = 'compareWith', default = 'best'},
    {file = 'live_difference', key = 'showLiveDifference', default = true}, {file = 'sector_bars', key = 'showSectorBars', default = true},
    {file = 'speeds', key = 'showSpeeds', default = true}, {file = 'forecast', key = 'showForecast', default = true},
}
-- los colores, al final del archivo y en este orden
for _, key in ipairs({'background', 'topBar', 'title', 'label', 'text', 'dim', 'best', 'better', 'worse', 'gain', 'loss'}) do
    SETTINGS[#SETTINGS + 1] = {file = COLOR_SETTINGS[key], key = COLOR_SETTINGS[key], default = ''}
end
-- hud.ini from version 0.9.17 and earlier: Spanish keys and values
local OLD_FILE_KEYS = {ultima = 'last_lap', mejor = 'best_lap', ideal = 'ideal_lap', total = 'event_total', objetivo = 'target',
    anteriores = 'previous_sectors', comparar = 'compare_with', directo = 'live_difference', barras = 'sector_bars'}
local OLD_VALUES = {actual = 'current', compacto = 'compact', mejor = 'best', anterior = 'previous'}

-- Writes the settings file with its explanation; values: file key -> text (the default if missing)
local function writeSettingsFile(path, values)
    local file = io.open(path, 'w')
    if not file then return end
    file:write('; Panel de tiempos del mod SWGR Telemetry · timing panel of the SWGR Telemetry mod\n')
    file:write('; enabled: true/false al arrancar (Ctrl+F10 lo muestra u oculta en carrera)\n')
    file:write('; style: current, sith o compact\n')
    file:write('; x, y: posición de 0 a 1 (0,0 = arriba a la izquierda) · scale: tamaño · opacity: fondo de 0 a 1\n')
    file:write('; last_lap, best_lap, ideal_lap, event_total, target: filas de abajo (true/false). En compact no hay fila last_lap,\n')
    file:write(';   y el total se oculta en los tramos de una sola vuelta\n')
    file:write('; speeds: velocidad punta y mínima de la vuelta · forecast: total previsto a tu ritmo (true/false)\n')
    file:write('; target: el más rápido entre tu amigo que te gana, tu récord y el nº1 del juego\n')
    file:write('; previous_sectors: sectores aún sin correr con el tiempo de la vuelta anterior en gris (true/false)\n')
    file:write('; compare_with: diferencia de cada sector frente a tu mejor sector (best) o a la vuelta anterior (previous)\n')
    file:write('; live_difference: diferencia en directo frente a tu mejor vuelta (true/false) · sector_bars: fila de barras de sector\n')
    file:write('; color_*: colores del panel en #RRGGBB (vacío = los del estilo; color_top_bar=none quita la barra de arriba)\n')
    local NUMBER_FORMATS = {x = '%.3f', y = '%.3f', scale = '%.2f', opacity = '%.2f'}
    for _, setting in ipairs(SETTINGS) do
        local value = values[setting.file]
        if value == nil then
            value = NUMBER_FORMATS[setting.file] and string.format(NUMBER_FORMATS[setting.file], setting.default) or tostring(setting.default)
        end
        file:write(setting.file .. '=' .. (OLD_VALUES[value:lower()] or value) .. '\n')
    end
    file:close()
end

-- Reads key=value lines; old Spanish keys are translated
local function readSettingsFile(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local values = {}
    for line in file:lines() do
        local key, value = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
        if key then values[OLD_FILE_KEYS[key] or key] = value end
    end
    file:close()
    return values
end

-- path: timing_panel.ini · oldPath: hud.ini of older versions, moved to the new file the first time
function TimingPanel.loadSettings(path, oldPath)
    local settings = {}
    for _, setting in ipairs(SETTINGS) do settings[setting.key] = setting.default end
    local values = readSettingsFile(path)
    if not values and oldPath then
        local oldValues = readSettingsFile(oldPath)
        if oldValues then
            writeSettingsFile(path, oldValues.style and oldValues or {})
            os.remove(oldPath)
            values = readSettingsFile(path)
        end
    end
    if not values then writeSettingsFile(path, {}); settings.styleTable = useStyle(settings.style, settings); return settings end
    -- A file from the versions before the panel styles (no "style", never edited by hand): the new panel's defaults
    if not values.style then
        writeSettingsFile(path, {})
        values = {}
    end
    for _, setting in ipairs(SETTINGS) do
        local value = values[setting.file]
        if value ~= nil then
            local default = setting.default
            if type(default) == 'boolean' then settings[setting.key] = value ~= 'false'
            elseif type(default) == 'number' then settings[setting.key] = tonumber(value) or default
            else
                value = value:lower()
                settings[setting.key] = OLD_VALUES[value] or value
            end
        end
    end
    if not STYLES[settings.style] then settings.style = 'compact' end
    if settings.compareWith ~= 'previous' then settings.compareWith = 'best' end
    settings.x = math.max(0, math.min(1, settings.x)); settings.y = math.max(0, math.min(1, settings.y))
    settings.scale = math.max(0.5, math.min(3, settings.scale)); settings.opacity = math.max(0, math.min(1, settings.opacity))
    settings.colors = {}
    for key, fileKey in pairs(COLOR_SETTINGS) do
        local value = settings[fileKey]
        if value and value ~= '' then settings.colors[key] = value end
    end
    settings.styleTable = useStyle(settings.style, settings)
    return settings
end

-- Bottom rows that are shown, in order and in groups (for the space between groups)
function TimingPanel.bottomRows(settings, lapCount)
    local style, rows = settings.styleTable, {}
    if settings.showLastLap and not style.isCompact then rows[#rows + 1] = {id = 'last_lap', group = 1} end
    if settings.showBestLap then rows[#rows + 1] = {id = 'best_lap', group = 1} end
    if settings.showIdealLap then rows[#rows + 1] = {id = 'ideal_lap', group = 1} end
    if settings.showSpeeds then rows[#rows + 1] = {id = 'speeds', group = 1} end
    if settings.showEventTotal and not (style.isCompact and lapCount == 1) then rows[#rows + 1] = {id = 'event_total', group = 2} end
    if settings.showForecast and lapCount ~= 1 then rows[#rows + 1] = {id = 'forecast', group = 2} end
    if settings.showTarget then rows[#rows + 1] = {id = 'target', group = 2} end
    return rows
end

local panelCount = 0

-- Creates the panel for sectorCount sectors and the given bottom rows.
-- Returns an object with setCell(row, column, text, color), rowOf(id), place(), show(), close().
function TimingPanel.createPanel(playerController, sectorCount, settings, bottomRows)
    local style = settings.styleTable
    panelCount = panelCount + 1
    local nameSuffix = tostring(os.time()) .. '_' .. panelCount
    local widgetCount = 0
    local function makeWidget(className, outer)
        widgetCount = widgetCount + 1
        local class = StaticFindObject('/Script/UMG.' .. className)
        assert(isValid(class), 'Falta la clase UMG ' .. className)
        local widget = StaticConstructObject(class, outer, FName('SWGRTimingPanel_' .. className .. '_' .. nameSuffix .. '_' .. widgetCount))
        assert(isValid(widget), 'No se pudo crear ' .. className)
        return widget
    end
    local width, padding, rowHeight = style.width, style.padding, style.rowHeight
    -- Vertical position of each row. Rows: 1 title, [live difference, large], [sector bars], sectors, bottom rows
    -- (6 px before the sectors and between the bottom groups)
    local rowY, rowIndexOf = {}, {}
    local y = padding + (style.topBar and 2 or 0)
    rowY[1] = y; y = y + rowHeight
    local rowCount = 1
    if settings.showLiveDifference then rowCount = rowCount + 1; rowY[rowCount] = y + 2; rowIndexOf.live_difference = rowCount; y = y + rowHeight + 8 end
    local barsY
    if settings.showSectorBars then barsY = y + 4; y = y + 12 else y = y + 6 end
    local firstSectorRow = rowCount
    for _ = 1, sectorCount do rowCount = rowCount + 1; rowY[rowCount] = y; y = y + rowHeight end
    local lastGroup = 0
    for _, bottomRow in ipairs(bottomRows) do
        if bottomRow.group ~= lastGroup then y = y + 6; lastGroup = bottomRow.group end
        rowCount = rowCount + 1; rowY[rowCount] = y; rowIndexOf[bottomRow.id] = rowCount
        y = y + rowHeight
    end
    local height = y + padding + 2

    local root = makeWidget('UserWidget', playerController)
    local widgetTree = makeWidget('WidgetTree', root); root.WidgetTree = widgetTree
    local canvas = makeWidget('CanvasPanel', widgetTree); widgetTree.RootWidget = canvas
    local background = makeWidget('Border', canvas)
    background:SetPadding({Left = 0, Top = 0, Right = 0, Bottom = 0})
    background:SetBrushColor({R = style.background[1], G = style.background[2], B = style.background[3], A = settings.opacity})
    local inner = makeWidget('CanvasPanel', background); background:SetContent(inner)
    local backgroundSlot = canvas:AddChildToCanvas(background)
    backgroundSlot:SetSize({X = width, Y = height})
    background:SetRenderTransformPivot({X = 0, Y = 0})
    background:SetRenderScale({X = settings.scale, Y = settings.scale})
    if style.topBar then
        local topBar = makeWidget('Border', inner)
        topBar:SetBrushColor({R = style.topBar[1], G = style.topBar[2], B = style.topBar[3], A = 1})
        local topBarSlot = inner:AddChildToCanvas(topBar)
        topBarSlot:SetPosition({X = 0, Y = 0}); topBarSlot:SetSize({X = width, Y = 2})
    end

    local cells = {}
    local function addCell(row, column, fontSize, justification)
        local textBlock = makeWidget('TextBlock', inner)
        textBlock.Font.Size = fontSize
        if justification then pcall(function() textBlock:SetJustification(justification) end) end
        local slot = inner:AddChildToCanvas(textBlock)
        slot:SetPosition({X = style.columnX[column], Y = rowY[row]}); slot:SetSize({X = style.columnWidths[column], Y = rowHeight + 2})
        cells[row .. ':' .. column] = {widget = textBlock, text = nil, color = nil}
    end
    local fontSizes = style.fontSizes
    local RIGHT = 2
    addCell(1, 1, fontSizes.titleLabel); addCell(1, 2, fontSizes.titleValue, RIGHT); addCell(1, 3, fontSizes.label, RIGHT)
    for row = 2, rowCount do
        if row == rowIndexOf.live_difference then
            addCell(row, 1, fontSizes.label); addCell(row, 2, fontSizes.titleValue + 5, RIGHT); addCell(row, 3, fontSizes.difference, RIGHT)
        else
            addCell(row, 1, fontSizes.label); addCell(row, 2, fontSizes.value, RIGHT); addCell(row, 3, fontSizes.difference, RIGHT)
        end
    end
    -- Sector bars: one per sector, across the width of the panel
    local sectorBars = {}
    if barsY then
        local gap, left, right = 3, style.columnX[1], width - style.columnX[1]
        local barWidth = (right - left - gap * (sectorCount - 1)) / sectorCount
        for index = 1, sectorCount do
            local bar = makeWidget('Border', inner)
            local barSlot = inner:AddChildToCanvas(bar)
            barSlot:SetPosition({X = left + (index - 1) * (barWidth + gap), Y = barsY}); barSlot:SetSize({X = barWidth, Y = 4})
            sectorBars[index] = {widget = bar, color = nil}
        end
    end
    root:AddToViewport(8900)
    root:SetVisibility(3)

    local panel = {root = root, sectorCount = sectorCount, bottomRowCount = #bottomRows, height = height,
        hasLiveDifference = settings.showLiveDifference, hasSectorBars = settings.showSectorBars}
    function panel.rowOf(id) return rowIndexOf[id] end
    function panel.sectorRow(index) return firstSectorRow + index end
    -- color nil = sector not driven yet (faint grey)
    function panel.setSectorBar(index, color)
        local bar = sectorBars[index]
        if not bar then return end
        local barColor = color or {R = 0.5, G = 0.45, B = 0.44, A = 0.25}
        if bar.color ~= barColor then
            local alpha = color and 1 or 0.25
            bar.widget:SetBrushColor({R = barColor.R, G = barColor.G, B = barColor.B, A = alpha}); bar.color = barColor
        end
    end
    function panel.setCell(row, column, text, color)
        local cell = row and cells[row .. ':' .. column]
        if not cell then return end
        text = text or ''
        if cell.text ~= text then cell.widget:SetText(FText(text)); cell.text = text end
        color = color or TimingPanel.COLORS.text
        if cell.color ~= color then cell.widget:SetColorAndOpacity({SpecifiedColor = color, ColorUseRule = 0}); cell.color = color end
    end
    function panel.place(viewportWidth, viewportHeight)
        local scaledWidth, scaledHeight = width * settings.scale, height * settings.scale
        backgroundSlot:SetPosition({X = settings.x * math.max(0, viewportWidth - scaledWidth), Y = settings.y * math.max(0, viewportHeight - scaledHeight)})
    end
    function panel.show(visible) if isValid(root) then root:SetVisibility(visible and 3 or 2) end end
    function panel.isAlive() return isValid(root) and root:IsInViewport() end
    function panel.close() if isValid(root) then root:RemoveFromParent() end end
    return panel
end

return TimingPanel
