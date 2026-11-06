-- SWGR Telemetry v0.9.28 (read only, for offline use)
-- Records position, speed and progress along the track's route; measures sectors between the
-- game's checkpoints and uses the official lap time (PlayerRaceEventComponent.PreviousLapTime)
-- for laps and records.
-- It never writes to game objects and never hooks game functions: it only reads.
-- Data sources taken from N0M4D's MiniMap and LapRecord.
-- Shortcuts: Ctrl+F9 pauses/resumes recording · Ctrl+F10 shows/hides the timing panel.

local VERSION = '0.9.31'   -- always the same as the app's
local VIRTUAL_SECTOR_LENGTH_CM = 250000   -- length of the virtual sectors of point-to-point stages
local SCRIPTS_FOLDER = assert(debug.getinfo(1, 'S').source:match('^@(.+[\\/])'))
local MOD_FOLDER = SCRIPTS_FOLDER .. '../'
-- 0.9.29: the files are sorted into folders (config, data, logs). The app and the package make the
-- folders (Lua cannot); while one is missing, its files stay in the main folder as before.
local function plainFileExists(path) local file = io.open(path, 'r'); if file then file:close(); return true end; return false end
local FILE_FOLDERS = {
    config = {'preferences.txt', 'timing_panel.ini', 'hud.ini'},
    data = {'best_times.txt', 'learned_tracks.txt', 'ghosts.txt', 'event_records.txt', 'game_records.txt', 'rivals.txt'},
    logs = {'log.txt', 'safe_mode.txt', 'operation_in_progress.txt', 'record_search.txt', 'record_search_progress.txt'},
}
local FOLDER_OF = {}
for folderName, names in pairs(FILE_FOLDERS) do
    local folder = MOD_FOLDER .. folderName .. '/'
    local probe = io.open(folder .. '.keep', 'a')   -- only works if the folder exists
    if probe then
        probe:close()
        for _, name in ipairs(names) do
            FOLDER_OF[name] = folder
            if plainFileExists(MOD_FOLDER .. name) and not plainFileExists(folder .. name) then os.rename(MOD_FOLDER .. name, folder .. name) end
        end
    end
end
local function modFile(name) return (FOLDER_OF[name] or MOD_FOLDER) .. name end
local SAMPLE_INTERVAL_MS = 20
-- Estela rehecha y más segura: el código está listo, pero cada jugador la activa en la app (ghost_trail,
-- apagada por defecto). Así, si el juego se cierra con la estela puesta, el modo seguro sabe que fue ella.
local GHOST_ENABLED, TRAIL_ENABLED = true, true
local ROUTE_SAMPLE_COUNT = 1024        -- route points used to compute progress along the route
local ROUTE_SAMPLES_PER_TICK = 64      -- the route is sampled a little each tick to avoid stutters
local LOST_DISTANCE_SQUARED = 15000 * 15000   -- further than 150 m from the nearby route: search the whole route
local SEARCH_WINDOW_SEGMENTS = 200     -- route segments (~2.5 m each) checked around the last position
local START_SPEED_KMH = 5              -- speed that marks the start of the race
local MIN_LAP_SECONDS, MAX_LAP_SECONDS = 5, 900
local GATE_RADIUS = 15000              -- radius of each checkpoint gate (150 m)
local AUTOPILOT_RATIO = 0.6            -- after the finish, dropping below 60 % of the speed = end of the event

-- Own log (log.txt): every message is written straight away, so we know what the mod was doing
-- even if the game closes abruptly and UE4SS never gets to save its own log.
local LOG_PATH, loggedLineCount = modFile('log.txt'), 0
-- Bonificación de tiempo (Precisión: cada punto que pasas resta tiempo al total). El juego la da acumulada
-- (CurrentBonusTime); se guarda cada cambio con su hora para descontarla de vueltas, sectores y DIF.
local bonusData = {}
-- Bonificación acumulada hasta el momento t (0 si el evento no tiene)
function bonusData.at(race, t)
    local total = 0
    for _, change in ipairs(race.bonusChanges or {}) do
        if change.time <= t + 1e-6 then total = change.total else break end
    end
    return total
end
-- Bonificación ganada entre dos momentos
function bonusData.between(race, from, to)
    if not race.usesBonus then return 0 end
    return bonusData.at(race, to) - bonusData.at(race, from)
end

local function log(message)
    local line = '[SWGRTelemetry] ' .. tostring(message)
    print(line .. '\n')
    loggedLineCount = loggedLineCount + 1
    if loggedLineCount > 6000 then return end   -- tope por sesión de juego
    local file = io.open(LOG_PATH, loggedLineCount == 1 and 'w' or 'a')
    if file then file:write(os.date('%H:%M:%S '), line, '\n'); file:close() end
end
local function isValid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end); return ok and result == true
end
local function fullName(object) return isValid(object) and object:GetFullName() or '' end
local function address(object) return isValid(object) and object:GetAddress() or nil end
local function readProperty(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end); return ok and value or nil
end
local function typeName(value) local ok, result = pcall(function() return value:type() end); return ok and result or type(value) end
local function toVector(value) return {X = value.X, Y = value.Y, Z = value.Z} end

-- Estela blanca y freno: campos del VehicleState que se guardan en bruto al final del CSV, y el código
-- de la columna 9 del fantasma. Todo en una tabla porque el script está al límite de 200 variables locales.
-- Coche: Drifting. Rasante: Knifing / KnifeScale. Vaina: AirBrakeScale / AirBrakeStrength.
-- Moto: EnergyBrakeState / EnergyBrakeCharge. Todos: Brake.
local vehicleStateData = {
    fields = {'Brake', 'Drifting', 'Knifing', 'KnifeScale', 'AirBrakeScale', 'AirBrakeStrength', 'EnergyBrakeState', 'EnergyBrakeCharge'},
    columns = 'brake,drifting,knifing,knife_scale,air_brake_scale,air_brake_strength,energy_brake_state,energy_brake_charge',
}

-- Lee un campo conservando el false (readProperty devuelve nil cuando el valor es false)
function vehicleStateData.readField(object, key)
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end

-- Valores de los campos en este momento; tabla vacía si no hay VehicleState
function vehicleStateData.read(race, pawn)
    if race.vehicleStatePawn ~= pawn then race.vehicleStatePawn, race.vehicleState = pawn, readProperty(pawn, 'VehicleState') end
    local values = {}
    if not isValid(race.vehicleState) then return values end
    for _, name in ipairs(vehicleStateData.fields) do values[name] = vehicleStateData.readField(race.vehicleState, name) end
    return values
end

-- Un valor para el CSV: true/false como 1/0, números con hasta 3 decimales, vacío si no se pudo leer
function vehicleStateData.valueText(value)
    if value == true then return '1' end
    if value == false then return '0' end
    if type(value) == 'number' then
        if value == math.floor(value) then return string.format('%d', value) end
        return string.format('%.3f', value)
    end
    return ''
end

-- Las columnas del CSV, separadas por comas y en el orden de fields
function vehicleStateData.csv(values)
    local texts = {}
    for index, name in ipairs(vehicleStateData.fields) do texts[index] = vehicleStateData.valueText(values[name]) end
    return table.concat(texts, ',')
end

-- Tipo de vehículo según el nombre del evento: CAR (coche), BIKE (moto), SKIMMER (rasante) o PLANE (vaina)
function vehicleStateData.vehicleType(race)
    local id = race.event and race.event.id or ''
    return id:match('_(CAR)_') or id:match('_(BIKE)_') or id:match('_(SKIMMER)_') or id:match('_(PLANE)_')
end

-- Activo: un true o un número mayor que 0
function vehicleStateData.isActive(value)
    return value == true or (type(value) == 'number' and value > 0)
end

-- Columna 9 del fantasma: W = estela blanca, B = freno, WB = las dos, - = ninguna, vacío = no se pudo leer.
-- Moto: el cuadrado va en dos tiempos. EnergyBrakeState 1 = cargando (mantienes el cuadrado y el juego
-- frena la moto), 2 y 3 = al soltar, se libera la carga (el impulso). W marca toda la maniobra (1 a 3), y
-- el frenado del estado 1 no cuenta como B porque es parte del cuadrado (prueba de 4 vueltas, 0.9.31).
function vehicleStateData.trailCode(vehicleType, values)
    if next(values) == nil then return '' end
    local isActive, white = vehicleStateData.isActive, false
    if vehicleType == 'CAR' then white = isActive(values.Drifting)
    elseif vehicleType == 'SKIMMER' then white = isActive(values.Knifing)
    elseif vehicleType == 'PLANE' then white = isActive(values.AirBrakeScale)
    elseif vehicleType == 'BIKE' then white = isActive(values.EnergyBrakeState)
    end
    local braking = isActive(values.Brake) and not (vehicleType == 'BIKE' and white)
    local code = (white and 'W' or '') .. (braking and 'B' or '')
    return code ~= '' and code or '-'
end
local function formatTime(seconds)
    if not seconds then return '--' end
    local minutes = math.floor(seconds / 60)
    return string.format('%d:%06.3f', minutes, seconds - minutes * 60)
end
local function formatDifference(seconds, best)
    if not best then return '' end
    return string.format(' (%+.3f)', seconds - best)
end
local function formatSignedDifference(seconds) return string.format('%+.3f', seconds) end

-- Texts of the timing panel, in the app's language (preferences.txt, written by the app):
-- Spanish, or English for 'en' and 'aurebesh' (the game's fonts have no Aurebesh)
local PANEL_TEXTS = {
    es = {lap = 'VUELTA ', stage = 'TRAMO', start = 'SALIDA', finish = 'FIN', last = 'ULTIMA', best = 'MEJOR', ideal = 'IDEAL',
          total = 'TOTAL', target = 'OBJETIVO', difference = 'DIF', record = 'RÉCORD', beaten = 'Nº1 BATIDO', perLap = '/v',
          forecast = 'PREVISTO', top = 'PUNTA', minimum = 'mín ', number1 = 'Nº1'},
    en = {lap = 'LAP ', stage = 'STAGE', start = 'START', finish = 'END', last = 'LAST', best = 'BEST', ideal = 'IDEAL',
          total = 'TOTAL', target = 'TARGET', difference = 'DELTA', record = 'RECORD', beaten = '#1 BEATEN', perLap = '/lap',
          forecast = 'FORECAST', top = 'TOP', minimum = 'min ', number1 = '#1'},
}
local panelTexts = PANEL_TEXTS.es
-- Your friends' best times (rivals.txt, written by the app from the pilot files: id \t time \t pilot)
local rivals = {}
local function readRivals()
    local found = {}
    local file = io.open(modFile('rivals.txt'), 'r')
    if file then
        for line in file:lines() do
            local id, time, pilot = line:match('^([^\t]+)\t([%d%.]+)\t(.*)$')
            if id and tonumber(time) then found[id] = {time = tonumber(time), pilot = pilot} end
        end
        file:close()
    end
    rivals = found
end
local function readPanelLanguage()
    local language = 'es'
    local file = io.open(modFile('preferences.txt'), 'r')
    if file then
        for line in file:lines() do
            local key, value = line:match('^([%w_]+)\t([%w_]*)')
            if key == 'language' then language = value end
        end
        file:close()
    end
    panelTexts = (language == 'en' or language == 'aurebesh') and PANEL_TEXTS.en or PANEL_TEXTS.es
end
pcall(readPanelLanguage)
local function sanitizeFileName(text) return (text:gsub('[^%w_%-]', '_')):sub(1, 60) end
local function fileExists(path)
    local file = io.open(path, 'r')
    if file then file:close(); return true end
    return false
end

---------------------------------------------------------------------------
-- Files from older versions (0.9.17 and earlier) had Spanish names. They are renamed once;
-- the app does the same with its own files and with the ones inside the tracks folder.
---------------------------------------------------------------------------
local RENAMED_FILES = {
    {'registro.txt', 'log.txt'}, {'bests.txt', 'best_times.txt'}, {'metas.txt', 'learned_tracks.txt'},
    {'fantasmas.txt', 'ghosts.txt'}, {'eventos.txt', 'event_records.txt'}, {'records_auto.txt', 'game_records.txt'},
    {'modo_seguro.txt', 'safe_mode.txt'}, {'en_curso.txt', 'operation_in_progress.txt'}, {'diag.txt', 'diagnostics.txt'},
    {'busqueda_records.txt', 'record_search.txt'}, {'busqueda_progreso.txt', 'record_search_progress.txt'},
}
local function renameOldFiles()
    for _, names in ipairs(RENAMED_FILES) do
        local oldPath, newPath = MOD_FOLDER .. names[1], modFile(names[2])
        if fileExists(oldPath) and not fileExists(newPath) then os.rename(oldPath, newPath) end
    end
    -- The tracks folder: renaming fails if the new one already exists (then the app merges both)
    os.rename(MOD_FOLDER .. 'circuitos', MOD_FOLDER .. 'tracks')
    -- The timing panel used to be hud.lua; the new one is timing_panel.lua
    if fileExists(SCRIPTS_FOLDER .. 'timing_panel.lua') and fileExists(SCRIPTS_FOLDER .. 'hud.lua') then os.remove(SCRIPTS_FOLDER .. 'hud.lua') end
end
pcall(renameOldFiles)
-- Keys saved by older versions: EV|<event>|<sectors>[|salida] and CARRERA|<session>|...
local function translateOldKey(key)
    return (key:gsub('^EV|', 'EVENT|'):gsub('^CARRERA|', 'RACE|'):gsub('|salida$', '|start'))
end

---------------------------------------------------------------------------
-- Best times kept between sessions (best_times.txt): key \t lap \t s1;s2;...
---------------------------------------------------------------------------
local BEST_TIMES_PATH = modFile('best_times.txt')
local bestTimes = {}
local bestTimesHaveOldKeys = false
local function loadBestTimes()
    local file = io.open(BEST_TIMES_PATH, 'r'); if not file then return end
    for line in file:lines() do
        local key, lapText, sectorsText = line:match('^([^\t]+)\t([^\t]*)\t([^\t]*)')
        if key then
            local best = {lap = tonumber(lapText), sectors = {}}
            -- Gaps are allowed (a sector without a time yet): "s1;;s3"
            local index = 0
            for value in (sectorsText .. ';'):gmatch('([^;]*);') do index = index + 1; best.sectors[index] = tonumber(value) end
            bestTimes[translateOldKey(key)] = best
            if translateOldKey(key) ~= key then bestTimesHaveOldKeys = true end
        end
    end
    file:close()
end
local function saveBestTimes()
    local lines = {}
    for key, best in pairs(bestTimes) do
        local sectorsText, sectorCount = {}, 0
        for index in pairs(best.sectors) do if type(index) == 'number' and index > sectorCount then sectorCount = index end end
        for index = 1, sectorCount do sectorsText[index] = best.sectors[index] and string.format('%.4f', best.sectors[index]) or '' end
        lines[#lines + 1] = key .. '\t' .. (best.lap and string.format('%.4f', best.lap) or '') .. '\t' .. table.concat(sectorsText, ';')
    end
    table.sort(lines)
    local file = io.open(BEST_TIMES_PATH, 'w')
    if file then file:write(table.concat(lines, '\n') .. '\n'); file:close() end
end
loadBestTimes()
if bestTimesHaveOldKeys then saveBestTimes() end   -- written once with the new keys

-- What the mod learns about each track and direction (learned_tracks.txt: key \t value), so the
-- timing panel works from the first lap on tracks it already knows:
--   finish|<track>  distance of the finish line · start|<track>  distance of the start of a stage
--   laps|<track>    number of laps of the event
local LEARNED_TRACKS_PATH = modFile('learned_tracks.txt')
local learnedTracks = {}
local learnedTracksHaveOldKeys = false
do
    local file = io.open(LEARNED_TRACKS_PATH, 'r')
    if file then
        for line in file:lines() do
            local key, value = line:match('^([^\t]+)\t([%d%.%-]+)')
            if key then
                local savedKey = key
                -- Older versions: no prefix for the finish line, "vueltas|" and "inicio|" for the others
                if key:find('^vueltas|') then key = key:gsub('^vueltas|', 'laps|')
                elseif key:find('^inicio|') then key = key:gsub('^inicio|', 'start|')
                elseif not key:find('^finish|') and not key:find('^laps|') and not key:find('^start|') then key = 'finish|' .. key end
                learnedTracks[key] = tonumber(value)
                if key ~= savedKey then learnedTracksHaveOldKeys = true end
            end
        end
        file:close()
    end
end
local function trackKey(race) return (race.track or race.label) .. '|' .. tostring(race.direction) end
local function saveLearnedTracks()
    local lines = {}
    for key, value in pairs(learnedTracks) do lines[#lines + 1] = string.format('%s\t%.10g', key, value) end
    table.sort(lines)
    local file = io.open(LEARNED_TRACKS_PATH, 'w')
    if file then file:write(table.concat(lines, '\n') .. '\n'); file:close() end
end
if learnedTracksHaveOldKeys then saveLearnedTracks() end   -- written once with the new keys

-- Timing panel (timing_panel.lua). If it fails, telemetry keeps working without the panel.
local timingPanelLibrary, timingPanelSettings
do
    local ok, library = pcall(dofile, SCRIPTS_FOLDER .. 'timing_panel.lua')
    if ok and type(library) == 'table' then
        timingPanelLibrary = library
        timingPanelSettings = library.loadSettings(modFile('timing_panel.ini'), modFile('hud.ini'))
    else
        log('Panel de tiempos no disponible: ' .. tostring(library))
    end
end

---------------------------------------------------------------------------
-- Game objects. FindAllOf walks every object and is expensive in this version of UE4SS: it is
-- only used when the saved reference stops being valid, and at most every 2 seconds.
---------------------------------------------------------------------------
local gameplayStatics = StaticFindObject('/Script/Engine.Default__GameplayStatics')
local cachedObjects = {playerController = nil, playerControllerScanAt = 0, gameState = nil, gameStateScanAt = 0,
    raceComponent = nil, raceComponentScanAt = 0}

local function findLocalPlayerController()
    if isValid(cachedObjects.playerController) and cachedObjects.playerController:IsLocalPlayerController() then return cachedObjects.playerController end
    cachedObjects.playerController = nil
    if os.clock() < cachedObjects.playerControllerScanAt then return end
    cachedObjects.playerControllerScanAt = os.clock() + 1
    for _, playerController in ipairs(FindAllOf('PlayerController') or {}) do
        if isValid(playerController) and playerController:IsLocalPlayerController() then
            cachedObjects.playerController = playerController; return playerController
        end
    end
end
local function findGameState(playerController)
    local world = address(playerController:GetWorld())
    if isValid(cachedObjects.gameState) and address(cachedObjects.gameState:GetWorld()) == world then return cachedObjects.gameState end
    cachedObjects.gameState = nil
    if os.clock() < cachedObjects.gameStateScanAt then return end
    cachedObjects.gameStateScanAt = os.clock() + 2
    for _, gameState in ipairs(FindAllOf('RacingGameState') or {}) do
        if isValid(gameState) and address(gameState:GetWorld()) == world then cachedObjects.gameState = gameState; return gameState end
    end
end
local function findRaceComponent(playerController)
    local playerState = readProperty(playerController, 'PlayerState')
    if not isValid(playerState) then return end
    if isValid(cachedObjects.raceComponent) and address(cachedObjects.raceComponent:GetOwner()) == address(playerState) then return cachedObjects.raceComponent end
    cachedObjects.raceComponent = nil
    if os.clock() < cachedObjects.raceComponentScanAt then return end
    cachedObjects.raceComponentScanAt = os.clock() + 2
    for _, component in ipairs(FindAllOf('PlayerRaceEventComponent') or {}) do
        if isValid(component) then
            local ok, owner = pcall(function() return component:GetOwner() end)
            if ok and address(owner) == address(playerState) then cachedObjects.raceComponent = component; return component end
        end
    end
end
local function findActiveRoute(playerController, gameState)
    local route = readProperty(gameState, 'RaceRoute')
    if isValid(route) and isValid(readProperty(route, 'mMainRouteSpline')) then return route end
    route = readProperty(readProperty(playerController.Pawn, 'RouteMarker'), 'mRoute')
    if isValid(route) and isValid(readProperty(route, 'mMainRouteSpline')) then return route end
end
-- Track identifier (tells the normal and reverse directions apart), as LapRecord does.
local function readTrackName(gameState)
    local ok, trackName = pcall(function()
        local viewModel = gameState.RaceEventViewModel
        if not isValid(viewModel) or not isValid(viewModel.track) then return nil end
        return viewModel.track:GetFName():ToString()
    end)
    return ok and trackName or nil
end
-- Arcade event identifier: the leaderboard the game uses
-- (e.g. LDB_ARC_TT_BIKE_DAL_A_SHORT_01 = time trial, bike, Lantaana short).
local readSafeText   -- reads texts after checking their type (defined further down)
local function readEventInfo(gameState)
    local viewModel = readProperty(gameState, 'RaceEventViewModel')
    if not isValid(viewModel) then return nil end
    local id
    local leaderboard = readProperty(viewModel, 'LeaderboardDef')
    if isValid(leaderboard) then pcall(function() id = leaderboard:GetFName():ToString() end) end
    local mode = readSafeText and readSafeText(viewModel, 'ModeName') or ''
    if mode == '' then mode = nil end
    return {id = id, mode = mode, laps = tonumber(readProperty(viewModel, 'NumLaps'))}
end

-- Only in Arcade is the vehicle fixed, so times can be compared between races.
-- In modes with a build (the campaign) every race is different: it is only compared with itself.
local function isArcadeRace(race)
    return race.event and race.event.id and race.event.id:find('^LDB_ARC') ~= nil
end

local function routeLabelOf(route)
    return fullName(route):match('/([%w_]+)%.[%w_]+:') or 'unknown_track'
end
local function chooseClock(world)
    if isValid(gameplayStatics) then
        local ok, seconds = pcall(function() return gameplayStatics:GetTimeSeconds(world) end)
        if ok and type(seconds) == 'number' then
            return function()
                local readOk, now = pcall(function() return gameplayStatics:GetTimeSeconds(world) end)
                return readOk and now or nil
            end, 'tiempo de juego'
        end
    end
    return os.clock, 'reloj del sistema'
end

---------------------------------------------------------------------------
-- Progress along the route (projection onto the sampled polyline)
---------------------------------------------------------------------------
local function projectOntoRoute(race, position, hintSegment)
    local points = race.routePoints
    local segmentCount = #points - 1
    local bestDistanceSquared, bestSegment, bestRouteDistance, bestRouteHeight = math.huge, 1, 0, 0
    local function testSegment(index)
        local segmentStart, segmentEnd = points[index], points[index + 1]
        local segmentX, segmentY, segmentZ = segmentEnd.X - segmentStart.X, segmentEnd.Y - segmentStart.Y, segmentEnd.Z - segmentStart.Z
        local lengthSquared = segmentX * segmentX + segmentY * segmentY + segmentZ * segmentZ
        local along = 0   -- fraction of the segment where the closest point is
        if lengthSquared > 0 then
            along = ((position.X - segmentStart.X) * segmentX + (position.Y - segmentStart.Y) * segmentY + (position.Z - segmentStart.Z) * segmentZ) / lengthSquared
            along = math.max(0, math.min(1, along))
        end
        local closestX, closestY, closestZ = segmentStart.X + segmentX * along, segmentStart.Y + segmentY * along, segmentStart.Z + segmentZ * along
        local offsetX, offsetY, offsetZ = position.X - closestX, position.Y - closestY, position.Z - closestZ
        local distanceSquared = offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ
        if distanceSquared < bestDistanceSquared then
            bestDistanceSquared, bestSegment, bestRouteHeight = distanceSquared, index, closestZ
            bestRouteDistance = segmentStart.distance + (segmentEnd.distance - segmentStart.distance) * along
        end
    end
    if hintSegment then
        for offset = -SEARCH_WINDOW_SEGMENTS, SEARCH_WINDOW_SEGMENTS do testSegment(((hintSegment - 1 + offset) % segmentCount) + 1) end
        if bestDistanceSquared > LOST_DISTANCE_SQUARED then return projectOntoRoute(race, position, nil) end
    else
        for index = 1, segmentCount do testSegment(index) end
    end
    return bestRouteDistance, bestSegment, math.sqrt(bestDistanceSquared), bestRouteHeight
end

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------
local function writeFile(path, text, mode)
    local file, openError = io.open(path, mode or 'a')
    if not file then log('No se puede escribir ' .. path .. ': ' .. tostring(openError)); return false end
    file:write(text); file:close(); return true
end
-- 0.9.29: the files of a race are only written once it is a real attempt (FILES_AFTER_SECONDS from the
-- start, or a lap done). A quick restart only adds one attempt to event_records.txt.
local FILES_AFTER_SECONDS = 20
local function flushTelemetryBuffer(race)
    if race.filesDeferred then return end
    if race.telemetryPath and #race.telemetryBuffer > 0 then
        writeFile(race.telemetryPath, table.concat(race.telemetryBuffer, '\n') .. '\n')
        race.telemetryBuffer = {}
    end
end
-- Makes sure a folder exists. Lua has no mkdir, so only Unreal's file library is tried: Windows'
-- mkdir (os.execute) would open a system window for a moment, and that takes a full-screen game out
-- of full screen. If the folder cannot be created the caller saves the files in the mod folder, and
-- the app moves them into their track's folder.
local function canOpenForAppend(probePath)
    local file = io.open(probePath, 'a')
    if file then file:close(); return true end
    return false
end
local function ensureFolder(path, probePath)
    if canOpenForAppend(probePath) then return true end
    local windowsPath = path:gsub('/', '\\'):gsub('\\+$', '')
    local fileUtilities = StaticFindObject('/Script/BlueprintFileUtils.Default__BlueprintFileUtilsBPLibrary')
    if isValid(fileUtilities) then pcall(function() fileUtilities:MakeDirectory(windowsPath, true) end) end
    return canOpenForAppend(probePath)
end
local function writeSummaryLine(race, text)
    log(text)
    if race.filesDeferred then race.pendingSummary[#race.pendingSummary + 1] = text
    elseif race.summaryPath then writeFile(race.summaryPath, text .. '\n') end
end
local function commitRaceFiles(race)
    if not race.filesDeferred then return end
    race.filesDeferred = false
    writeFile(race.telemetryPath, race.pendingHeader, 'w')
    if #race.pendingSummary > 0 then writeFile(race.summaryPath, table.concat(race.pendingSummary, '\n') .. '\n', 'w') end
    race.pendingSummary = {}
    flushTelemetryBuffer(race)
end

---------------------------------------------------------------------------
-- Race
-- The finish line is where the game publishes the official lap time (it does not have to be the
-- start of the route's spline): the checkpoint crossed at that moment is taken. Sectors are the
-- stretches between checkpoints within each official lap, so they add up exactly to the official time.
---------------------------------------------------------------------------
local modState = {recordingEnabled = true, race = nil, recordingChordDown = false, panelChordDown = false, missingVehicleTicks = 0,
    timingPanel = nil, timingPanelVisible = true, timingPanelRetryAt = 0, ticks = 0}
local KEYS = {f9 = {KeyName = FName('F9')}, f10 = {KeyName = FName('F10')}, f11 = {KeyName = FName('F11')},
    leftControl = {KeyName = FName('LeftControl')}, rightControl = {KeyName = FName('RightControl')}}

---------------------------------------------------------------------------
-- Safe mode. If the game closes abruptly while the mod is doing something delicate (creating the
-- panel, reading the records, the record search, hooking into the race), that part is switched off
-- the next time the game opens and noted in safe_mode.txt; the app shows it. If errors keep coming
-- (for example after a game patch), recording stops for that session instead of insisting.
-- Deleting safe_mode.txt (or installing a new version of the mod) tries everything again.
---------------------------------------------------------------------------
local SAFE_MODE_PATH, OPERATION_IN_PROGRESS_PATH = modFile('safe_mode.txt'), modFile('operation_in_progress.txt')
local SAFE_MODE_OPERATION_NAMES = {timing_panel = 'el panel de tiempos', game_records = 'leer tus récords del juego',
    record_search = 'la búsqueda de récords', race_hook = 'engancharse a la carrera', recording = 'la grabación',
    event_names = 'leer los nombres de evento del juego', race_ghost = 'el fantasma en pista', ghost_look = 'el aspecto del fantasma', ghost_vehicle = 'copiar tu vehículo para el fantasma', ghost_trail = 'la estela del fantasma', ghost_flame = 'la llama del fantasma', ghost_game_flame = 'la llama del juego en el fantasma'}
-- Operation names written by older versions (in operation_in_progress.txt, then en_curso.txt)
local OLD_OPERATION_NAMES = {panel = 'timing_panel', records = 'game_records', busqueda = 'record_search', carrera = 'race_hook',
    grabacion = 'recording', nombres = 'event_names'}
local safeMode = {blocked = {}, entries = {}}
local function saveSafeMode()
    local lines = {}
    for _, entry in ipairs(safeMode.entries) do
        lines[#lines + 1] = table.concat({entry.operation, entry.scope, entry.reason, entry.date, entry.version}, '\t')
    end
    if #lines == 0 then os.remove(SAFE_MODE_PATH) else writeFile(SAFE_MODE_PATH, table.concat(lines, '\n') .. '\n', 'w') end
end
-- scope: 'blocked' (until safe_mode.txt is deleted) or 'session' (only this game session)
local function blockOperation(operation, scope, reason)
    safeMode.blocked[operation] = true
    safeMode.entries[#safeMode.entries + 1] = {operation = operation, scope = scope, reason = (tostring(reason):gsub('[\t\r\n]+', ' ')):sub(1, 200),
        date = os.date('%Y-%m-%d %H:%M'), version = VERSION}
    saveSafeMode()
    log('MODO SEGURO: desactivado ' .. (SAFE_MODE_OPERATION_NAMES[operation] or operation) .. ' (' .. tostring(reason) .. ')' ..
        (scope == 'blocked' and '. Borra safe_mode.txt para volver a intentarlo.' or ' en esta partida.'))
end
local function loadSafeMode()
    local file = io.open(SAFE_MODE_PATH, 'r')
    if file then
        for line in file:lines() do
            local operation, scope, reason, date, version = line:match('^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t\r]*)')
            -- What is blocked stays blocked; what was only for one session or for another version is forgotten
            if operation and scope == 'blocked' and version == VERSION then
                safeMode.entries[#safeMode.entries + 1] = {operation = operation, scope = scope, reason = reason, date = date, version = version}
                safeMode.blocked[operation] = true
            end
        end
        file:close()
    end
    saveSafeMode()
    for operation in pairs(safeMode.blocked) do
        log('MODO SEGURO: sigue desactivado ' .. (SAFE_MODE_OPERATION_NAMES[operation] or operation) .. ' (borra safe_mode.txt para volver a intentarlo).')
    end
    local inProgress = io.open(OPERATION_IN_PROGRESS_PATH, 'r')
    if inProgress then
        local operation = (inProgress:read('*l') or ''):match('^%s*(%S+)')
        inProgress:close(); os.remove(OPERATION_IN_PROGRESS_PATH)
        operation = operation and (OLD_OPERATION_NAMES[operation] or operation)
        if operation and SAFE_MODE_OPERATION_NAMES[operation] and not safeMode.blocked[operation] then
            blockOperation(operation, 'blocked', 'la última vez el juego se cerró de golpe mientras el mod hacía esto')
        end
    end
end
-- Runs a delicate part, leaving a note in operation_in_progress.txt while it lasts
local guardedOperationStack = {}
local function runGuarded(operation, action, ...)
    if safeMode.blocked[operation] then return false, 'desactivado por el modo seguro' end
    guardedOperationStack[#guardedOperationStack + 1] = operation
    writeFile(OPERATION_IN_PROGRESS_PATH, operation .. '\n', 'w')
    local results = table.pack(pcall(action, ...))
    guardedOperationStack[#guardedOperationStack] = nil
    -- if this ran inside another delicate part, the note goes back to that part
    if #guardedOperationStack > 0 then writeFile(OPERATION_IN_PROGRESS_PATH, guardedOperationStack[#guardedOperationStack] .. '\n', 'w')
    else os.remove(OPERATION_IN_PROGRESS_PATH) end
    return table.unpack(results, 1, results.n)
end
loadSafeMode()

-- Ghost look (0.9.29): the mod cannot create materials, so it looks once per session (while the
-- circuit loads) for a translucent material already in the game that takes a texture, and lists
-- what it finds in race_ghosts\materials.txt. race_ghosts\material.txt (one full name) forces one.
-- race_ghosts\ghost.png, if it exists, is put on the sphere. Only names and settings are read.
local ghostLook = {searched = false, candidates = {}}
local BLEND_MODE_NAMES = {[0] = 'opaco', [1] = 'máscara', [2] = 'translúcido', [3] = 'aditivo', [4] = 'modulado'}
local function parameterNames(object, arrayName)
    local names = {}
    pcall(function()
        object[arrayName]:ForEach(function(_, element)
            local value = element:get()
            local nameOk, name = pcall(function() return value.ParameterInfo.Name:ToString() end)
            if nameOk and name then names[#names + 1] = name end
        end)
    end)
    return names
end
local function blendModeOf(material)
    for _ = 1, 8 do
        if not isValid(material) then return nil end
        local overrideOk, mode = pcall(function()
            local overrides = material.BasePropertyOverrides
            if overrides and overrides.bOverride_BlendMode then return overrides.BlendMode end
        end)
        if overrideOk and mode ~= nil then return tonumber(mode) end
        local parentOk, parent = pcall(function() return material.Parent end)
        if parentOk and isValid(parent) then material = parent
        else
            local ok, ownMode = pcall(function() return material.BlendMode end)
            return ok and tonumber(ownMode) or nil
        end
    end
end
local function searchGhostMaterials()
    if ghostLook.searched then return end
    ghostLook.searched = true
    local startedAt, lines, candidates, counted = os.clock(), {}, {}, 0
    for _, className in ipairs({'MaterialInstanceConstant', 'Material'}) do
        for _, material in ipairs(FindAllOf(className) or {}) do
            counted = counted + 1
            local mode = blendModeOf(material)
            if mode and mode >= 2 then
                local textures = parameterNames(material, 'TextureParameterValues')
                local scalars = parameterNames(material, 'ScalarParameterValues')
                local vectors = parameterNames(material, 'VectorParameterValues')
                local nameOk, fullName = pcall(function() return material:GetFullName() end)
                if nameOk and fullName then
                    if fullName:find('Widget3DPassThrough', 1, true) then
                        -- the engine's material for 3D widgets: its parent has an image (SlateUI) and a tint with opacity
                        textures = {'SlateUI'}; vectors = {'TintColorAndOpacity'}; scalars = {'OpacityFromTexture'}
                    end
                    local entry = {material = material, name = fullName, mode = mode, textures = textures, scalars = scalars, vectors = vectors}
                    entry.score = (mode == 2 and 10 or 0) + (#textures > 0 and 5 or 0) + (#scalars > 0 and 1 or 0) + (fullName:find('^MaterialInstanceConstant') and 1 or 0)
                    candidates[#candidates + 1] = entry
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    ghostLook.candidates = candidates
    lines[#lines + 1] = string.format('== Materiales para el fantasma %s · %d revisados, %d translúcidos o aditivos · %.1f s',
        os.date('%Y-%m-%d %H:%M:%S'), counted, #candidates, os.clock() - startedAt)
    for index, entry in ipairs(candidates) do
        if index > 200 then break end
        lines[#lines + 1] = string.format('%s | %s | texturas: %s | escalares: %s | colores: %s', entry.name, BLEND_MODE_NAMES[entry.mode] or tostring(entry.mode),
            table.concat(entry.textures, ', '), table.concat(entry.scalars, ', '), table.concat(entry.vectors, ', '))
    end
    writeFile(MOD_FOLDER .. 'race_ghosts/materials.txt', table.concat(lines, '\n') .. '\n', 'w')
    log(string.format('Fantasma: %d materiales translúcidos encontrados (%.1f s), lista en race_ghosts\\materials.txt', #candidates, os.clock() - startedAt))
end
-- Puts the chosen material, the image and the transparency on the sphere. Returns a short note for the log.
local function dressGhostSphere(actor, world)
    local component = readProperty(actor, 'StaticMeshComponent')
    local chosen
    local file = io.open(MOD_FOLDER .. 'race_ghosts/material.txt', 'r')
    if file then
        local wanted = (file:read('*l') or ''):gsub('^%s+', ''):gsub('%s+$', ''); file:close()
        for _, entry in ipairs(ghostLook.candidates) do if entry.name == wanted or entry.name:find(wanted, 1, true) then chosen = entry; break end end
    end
    chosen = chosen or ghostLook.candidates[1]
    if not chosen then return 'sin material translúcido: esfera normal' end
    local materials = StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
    local dynamic
    pcall(function() dynamic = materials:CreateDynamicMaterialInstance(world, chosen.material, FName('GhostMaterial'), 0) end)
    if not isValid(dynamic) then pcall(function() dynamic = component:CreateDynamicMaterialInstance(0, chosen.material, FName('GhostMaterial')) end) end
    if not isValid(dynamic) then return 'no se pudo crear el material ' .. chosen.name end
    pcall(function() component:SetMaterial(0, dynamic) end)
    local notes = {'material ' .. (chosen.name:match('([^%.:/ ]+)$') or chosen.name)}
    local imagePath = (MOD_FOLDER .. 'race_ghosts/ghost.png')
    local imageFile = io.open(imagePath, 'rb')
    if imageFile then
        imageFile:close()
        local rendering = StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
        local texture
        pcall(function() texture = rendering:ImportFileAsTexture2D(world, (imagePath:gsub('/', '\\'))) end)
        if isValid(texture) and #chosen.textures > 0 then
            for _, name in ipairs(chosen.textures) do pcall(function() dynamic:SetTextureParameterValue(FName(name), texture) end) end
            notes[#notes + 1] = 'imagen en ' .. table.concat(chosen.textures, ', ')
            local checkOk, applied = pcall(function() return dynamic:K2_GetTextureParameterValue(FName(chosen.textures[1])) end)
            notes[#notes + 1] = 'comprobada: ' .. (checkOk and isValid(applied) and 'sí' or 'no')
        else
            notes[#notes + 1] = isValid(texture) and 'el material no admite imagen' or 'no se pudo leer ghost.png'
        end
    end
    for _, name in ipairs(chosen.scalars) do
        if name == 'OpacityFromTexture' then pcall(function() dynamic:SetScalarParameterValue(FName(name), 1) end)
        elseif name:lower():find('opac') then pcall(function() dynamic:SetScalarParameterValue(FName(name), 0.5) end); notes[#notes + 1] = name .. ' 0.5' end
    end
    for _, name in ipairs(chosen.vectors) do
        if name == 'TintColorAndOpacity' then
            pcall(function() dynamic:SetVectorParameterValue(FName(name), {R = 1, G = 1, B = 1, A = 0.5}) end); notes[#notes + 1] = 'transparencia 0.5'
        end
    end
    return table.concat(notes, ' · ')
end
local OFFICIAL_TIME_WAIT_SECONDS = 0.3    -- wait after the official time to see the checkpoint crossing
local OFFICIAL_TIME_MATCH_SECONDS = 1.0   -- largest time gap between the official time and a crossing

local checkEventEnd, updateEventRecord

-- Ghost of the best lap (ghosts.txt): distance covered in the lap (cm) and the time at that point,
-- every ~10 m. Used for the live difference on the timing panel.
local GHOSTS_PATH = modFile('ghosts.txt')
local ghosts = {}
local ghostsHaveOldKeys = false
local function loadGhosts()
    local file = io.open(GHOSTS_PATH, 'r')
    if file then
        for line in file:lines() do
            local key, lapTime, pointsText = line:match('^([^\t]+)\t([%d%.]+)\t(.*)$')
            if key then
                local ghost = {lapTime = tonumber(lapTime), distances = {}, times = {}}
                for distance, time in pointsText:gmatch('([%d%.%-]+):([%d%.%-]+)') do
                    ghost.distances[#ghost.distances + 1] = tonumber(distance); ghost.times[#ghost.times + 1] = tonumber(time)
                end
                if #ghost.distances > 1 then
                    ghosts[translateOldKey(key)] = ghost
                    if translateOldKey(key) ~= key then ghostsHaveOldKeys = true end
                end
            end
        end
        file:close()
    end
end
loadGhosts()
local function saveGhosts()
    local keys = {}
    for key in pairs(ghosts) do keys[#keys + 1] = key end
    table.sort(keys)
    local lines = {}
    for _, key in ipairs(keys) do
        local ghost, points = ghosts[key], {}
        for index = 1, #ghost.distances do points[index] = string.format('%.0f:%.3f', ghost.distances[index], ghost.times[index]) end
        lines[#lines + 1] = key .. '\t' .. string.format('%.3f', ghost.lapTime) .. '\t' .. table.concat(points, ';')
    end
    local file = io.open(GHOSTS_PATH, 'w')
    if file then file:write(table.concat(lines, '\n') .. '\n'); file:close() end
end
if ghostsHaveOldKeys then saveGhosts() end   -- written once with the new keys
-- Ghost time when it reaches the given distance (interpolated); nil outside its run
local function ghostTimeAtDistance(ghost, distance)
    local distances, times = ghost.distances, ghost.times
    if not distances or #distances < 2 or distance < distances[1] or distance > distances[#distances] then return nil end
    local low, high = 1, #distances
    while high - low > 1 do
        local middle = (low + high) // 2
        if distances[middle] <= distance then low = middle else high = middle end
    end
    local span = distances[high] - distances[low]
    local fraction = (distance - distances[low]) / (span ~= 0 and span or 1)
    return times[low] + fraction * (times[high] - times[low])
end
-- Stores as ghost the trace of the lap [lapStart, lapEnd] (points every ~10 m).
-- origin: the same moment the panel counts from (at the start, when crossing the line), so the
-- live difference compares like with like.
local function storeGhost(race, key, lapStart, lapEnd, lapTime, origin)
    origin = origin or lapStart
    local ghost = {lapTime = lapTime, distances = {0}, times = {0}}
    local lastDistance = 0
    for _, point in ipairs(race.distanceTrace or {}) do
        if point.time > lapStart and point.time < lapEnd and point.distance > lastDistance + 1000 then
            ghost.distances[#ghost.distances + 1] = point.distance
            ghost.times[#ghost.times + 1] = point.time - origin - bonusData.between(race, origin, point.time)
            lastDistance = point.distance
        end
    end
    if #ghost.distances < 10 then return end
    ghosts[key] = ghost
    race.ghostsChanged = true   -- se guarda al terminar el evento (un reinicio no cuenta)
end

local function propertyTypeName(property)
    local ok, result = pcall(function() return property:GetClass():GetFName():ToString() end)
    return ok and result or '?'
end
-- Solo cuentan las carreras terminadas: los mejores tiempos y fantasmas del DIF que mejora una carrera se
-- guardan al terminarla (saveRaceBests). Si se deja a medias, se vuelven a leer los del disco (discardRaceBests).
local function saveRaceBests(race)
    if race.bestTimesChanged then saveBestTimes(); race.bestTimesChanged = nil end
    if race.ghostsChanged then saveGhosts(); race.ghostsChanged = nil end
end
local function discardRaceBests(race)
    if race.bestTimesChanged then
        for key in pairs(bestTimes) do bestTimes[key] = nil end
        loadBestTimes()
        race.bestTimesChanged = nil
    end
    if race.ghostsChanged then
        for key in pairs(ghosts) do ghosts[key] = nil end
        loadGhosts()
        race.ghostsChanged = nil
    end
end
local function endRace(reason)
    local race = modState.race
    if not race then return end
    if race.ghost then local actors = race.ghost.actors or {race.ghost.actor}; race.ghost = nil; for _, actor in ipairs(actors) do pcall(function() if isValid(actor) then actor:K2_DestroyActor() end end) end end
    if race.eventEnded and race.lapNumber > 0 then
        local key = 'laps|' .. trackKey(race)
        if not learnedTracks[key] or race.lapNumber > learnedTracks[key] then
            learnedTracks[key] = race.lapNumber; saveLearnedTracks(); log('Vueltas del evento aprendidas: ' .. race.lapNumber)
        end
    end
    if race.filesDeferred then
        if not race.eventEnded then discardRaceBests(race) end
        if race.startTime and race.event and race.event.id and race.event.id:find('^LDB_ARC') then
            pcall(updateEventRecord, race, nil)
            log('Carrera cerrada (' .. reason .. '): reinicio rápido, se cuenta el intento sin guardar archivos')
        else
            log('Carrera cerrada (' .. reason .. ') antes de la salida: sin archivos')
        end
    else
        if race.eventEnded or not race.startTime then
            -- finished events count their attempt in finishEvent
        elseif race.event and race.event.id and race.event.id:find('^LDB_ARC') then pcall(updateEventRecord, race, nil) end
        flushTelemetryBuffer(race)
        if not race.eventEnded and race.startTime then
            -- Intento sin terminar (reinicio): cuenta como intento y queda en el resumen, pero sin telemetría
            -- ni mejores tiempos: solo cuentan las carreras completas
            discardRaceBests(race)
            if race.telemetryPath then os.remove(race.telemetryPath) end
            writeSummaryLine(race, 'Intento sin terminar (reinicio): no se guardan telemetría ni mejores tiempos')
            log('Carrera cerrada (' .. reason .. '): intento sin terminar')
        elseif race.telemetryPath then log('Carrera cerrada (' .. reason .. '): ' .. race.telemetryPath) end
    end
    modState.race = nil
    if modState.timingPanel then pcall(modState.timingPanel.close); modState.timingPanel = nil end
end

local function createRace(playerController, gameState, route, key)
    local spline = route.mMainRouteSpline
    local routeLength = spline:GetSplineLength()
    assert(type(routeLength) == 'number' and routeLength > 0 and routeLength < math.huge, 'Longitud de ruta no válida')
    local track = readTrackName(gameState)
    local race = {key = key, route = route, spline = spline, routeLength = routeLength, routePoints = {}, nextRouteSample = 0,
        track = track, label = sanitizeFileName(track or routeLabelOf(route)),
        world = playerController:GetWorld(), gameState = gameState, event = readEventInfo(gameState), telemetryBuffer = {},
        checkpointPositions = {}, crossings = {}, lastCrossingTimes = {}, lapNumber = 0, resetTimes = {},
        liveLap = {running = false, sectorTimes = {}}}
    local checkpoints = readProperty(route, 'Checkpoints')
    if typeName(checkpoints) == 'TArray' and #checkpoints <= 64 then
        checkpoints:ForEach(function(_, element)
            local ok, actor = pcall(function() return element:get() end)
            if ok and isValid(actor) then
                local locationOk, position = pcall(function() return toVector(actor:K2_GetActorLocation()) end)
                if locationOk then race.checkpointPositions[#race.checkpointPositions + 1] = position end
            end
        end)
    end
    log(string.format('Circuito detectado: %s (%.0f m, %d checkpoints). Preparando ruta...', race.label, routeLength / 100, #race.checkpointPositions))
    -- Limpieza de memoria durante la carga, donde un tirón no se nota
    collectgarbage('collect')
    -- Ajustes del panel en carrera: se vuelven a leer en cada carrera (la app los cambia en Opciones)
    if timingPanelLibrary then
        local settingsOk, newSettings = pcall(timingPanelLibrary.loadSettings, modFile('timing_panel.ini'))
        if settingsOk and newSettings then timingPanelSettings = newSettings end
        if modState.timingPanel then pcall(modState.timingPanel.close); modState.timingPanel = nil end
    end
    if GHOST_ENABLED and not ghostLook.searched and not safeMode.blocked.ghost_look then
        local searchOk, searchError = runGuarded('ghost_look', searchGhostMaterials)
        if not searchOk then log('Fantasma: búsqueda de materiales fallida: ' .. tostring(searchError)) end
    end
    return race
end

local function finishRouteSampling(race)
    local points = race.routePoints
    local first, last = points[1], points[#points]
    local dx, dy, dz = last.X - first.X, last.Y - first.Y, last.Z - first.Z
    race.isClosedCircuit = dx * dx + dy * dy + dz * dz < 2000 * 2000
    race.checkpointRouteDistances, race.routeGates = {}, {}
    local pointCount = #points
    -- Point-to-point stage with only a start and a finish (the game has no sectors): it is split into
    -- equal stretches of about 2.5 km with virtual checkpoints, to see where you gain or lose time.
    if not race.isClosedCircuit and #race.checkpointPositions == 2 then
        local startDistance = projectOntoRoute(race, race.checkpointPositions[1], nil)
        local finishDistance = projectOntoRoute(race, race.checkpointPositions[2], nil)
        local span = math.abs(finishDistance - startDistance)
        local virtualCount = math.max(2, math.min(8, math.floor(span / VIRTUAL_SECTOR_LENGTH_CM + 0.5)))
        if span > 2 * 50000 then
            for index = 1, virtualCount - 1 do
                local ok, position = pcall(function()
                    return toVector(race.spline:GetWorldLocationAtDistanceAlongSpline(startDistance + (finishDistance - startDistance) * index / virtualCount))
                end)
                if ok and position then race.checkpointPositions[#race.checkpointPositions + 1] = position end
            end
            race.virtualSectorCount = virtualCount
        end
    end
    for _, position in ipairs(race.checkpointPositions) do
        local routeDistance, segment = projectOntoRoute(race, position, nil)
        race.checkpointRouteDistances[#race.checkpointRouteDistances + 1] = routeDistance
        local before = points[math.max(1, segment - 2)]
        local after = points[math.min(pointCount, segment + 3)]
        local tx, ty, tz = after.X - before.X, after.Y - before.Y, after.Z - before.Z
        local tangentLength = math.sqrt(tx * tx + ty * ty + tz * tz)
        if tangentLength < 1 then tangentLength = 1 end
        race.routeGates[#race.routeGates + 1] = {routeDistance = routeDistance, position = position,
            tangent = {X = tx / tangentLength, Y = ty / tangentLength, Z = tz / tangentLength}}
    end
    table.sort(race.checkpointRouteDistances)
    local clockName
    race.clock, clockName = chooseClock(race.world)
    race.clockStart = race.clock() or 0
    local sessionStamp = os.date('%Y%m%d_%H%M%S')
    local folder = MOD_FOLDER .. 'tracks/' .. race.label .. '/'
    local routePath, basePath
    if ensureFolder(folder, folder .. 'history.txt') then
        routePath, basePath = folder .. 'route.csv', folder .. sessionStamp
        race.historyPath = folder .. 'history.txt'
    else
        log('Circuito nuevo: la sesión se guarda en la carpeta del mod y la app la pasará a tracks\\' .. race.label)
        routePath, basePath = MOD_FOLDER .. 'route_' .. race.label .. '.csv', MOD_FOLDER .. 'telemetry_' .. sessionStamp .. '_' .. race.label
    end
    race.sessionStamp = sessionStamp
    race.telemetryPath, race.summaryPath = basePath .. '.csv', basePath .. '_summary.txt'
    race.filesDeferred, race.pendingSummary = true, {}
    race.pendingHeader = 'time,lap,lap_time,distance,progress,x,y,z,velocity_x,velocity_y,velocity_z,kmh,heading,offset_from_route,height_above_route,event,boost,' .. vehicleStateData.columns .. '\n'
    -- Route geometry for the app (distances in the direction of the spline)
    local routeLines = {'type,distance,x,y,z'}
    for _, point in ipairs(points) do
        routeLines[#routeLines + 1] = string.format('point,%.1f,%.1f,%.1f,%.1f', point.distance, point.X, point.Y, point.Z)
    end
    for _, position in ipairs(race.checkpointPositions) do
        routeLines[#routeLines + 1] = string.format('checkpoint,%.1f,%.1f,%.1f,%.1f', (projectOntoRoute(race, position, nil)), position.X, position.Y, position.Z)
    end
    writeFile(routePath, table.concat(routeLines, '\n') .. '\n', 'w')
    writeSummaryLine(race, string.format('== %s | %s | %s | %.0f m | v%s | %d checkpoints | reloj: %s | vuelta oficial: %s',
        os.date('%Y-%m-%d %H:%M:%S'), race.label, race.isClosedCircuit and 'circuito cerrado' or 'tramo abierto',
        race.routeLength / 100, VERSION, #race.checkpointRouteDistances, clockName, isValid(race.raceComponent) and 'sí' or 'no encontrada'))
    if race.event and race.event.id then
        writeSummaryLine(race, string.format('Evento: %s | modo: %s | vueltas: %s', race.event.id, tostring(race.event.mode), tostring(race.event.laps)))
    end
    if race.virtualSectorCount then
        writeSummaryLine(race, string.format('Sectores: virtuales (%d tramos iguales; el juego no tiene sectores en este trazado)', race.virtualSectorCount))
    end
    if not isArcadeRace(race) then
        writeSummaryLine(race, 'Modo con build (no Arcade): esta carrera no cuenta para tus récords; el panel compara solo con sus propias vueltas.')
    end
end

local function sampleRouteStep(race)
    local sampleCount = ROUTE_SAMPLE_COUNT
    for _ = 1, ROUTE_SAMPLES_PER_TICK do
        if race.nextRouteSample > sampleCount then break end
        local distance = race.routeLength * race.nextRouteSample / sampleCount
        local position = race.spline:GetWorldLocationAtDistanceAlongSpline(distance)
        race.routePoints[#race.routePoints + 1] = {X = position.X, Y = position.Y, Z = position.Z, distance = distance}
        race.nextRouteSample = race.nextRouteSample + 1
    end
    if race.nextRouteSample > sampleCount then
        race.nextRouteSample = nil
        finishRouteSampling(race)
    end
end

-- Start lap: lap 1 of an event with several laps. You start slower, so it has its own best sectors,
-- lap and ghost, and does not spoil those of the flying laps.
local function isStartLap(race, lapNumber) return lapNumber == 1 and (race.lapCount or 0) > 1 end
local function bestTimesKey(race, sectorCount, startLap)
    if startLap then return bestTimesKey(race, sectorCount) .. '|start' end
    local vehicleType = readProperty(race.raceComponent, 'ChosenVehicleType')
    local base = race.track or string.format('%s|%d|%d', race.label, race.direction, math.floor(race.routeLength / 100))
    -- Key used before events were identified (same track and vehicle)
    local beforeEventsKey = string.format('%s|vt%s|%d', base, tostring(vehicleType or '?'), sectorCount)
    if isArcadeRace(race) then
        local key = 'EVENT|' .. race.event.id .. '|' .. sectorCount
        -- Arranque lanzado: tiempos desde el GO, con su propia clave (los antiguos, desde la puerta, no valen)
        -- Con bonificación (Precisión), los tiempos con ella descontada, también con su propia clave
        if race.rollingStart or race.usesBonus then return key .. (race.rollingStart and '|rolling' or '') .. (race.usesBonus and '|bonus' or '') end
        if not bestTimes[key] and bestTimes[beforeEventsKey] then bestTimes[key] = bestTimes[beforeEventsKey] end
        return key
    end
    return 'RACE|' .. tostring(race.sessionStamp) .. '|' .. beforeEventsKey
end

-- Sets the finish checkpoint and the order of the sectors from it.
local function setFinishLine(race, checkpoint)
    race.finishCheckpoint = checkpoint
    local routeLength, finishDistance = race.routeLength, race.checkpointDistances[checkpoint]
    local order = {}
    for index in ipairs(race.checkpointDistances) do if index ~= checkpoint then order[#order + 1] = index end end
    table.sort(order, function(a, b)
        return (race.checkpointDistances[a] - finishDistance + routeLength) % routeLength < (race.checkpointDistances[b] - finishDistance + routeLength) % routeLength
    end)
    race.startCheckpoint = nil
    if not race.isClosedCircuit and race.startDistance then
        for position, index in ipairs(order) do
            if math.abs(race.checkpointDistances[index] - race.startDistance) < 1000 then
                race.startCheckpoint = index; table.remove(order, position); break
            end
        end
    end
    -- Arranque lanzado: la puerta es el final del S1 y los checkpoints de la carrerilla no cuentan
    if race.rollingStart and race.startCheckpoint then
        local afterGate = {race.startCheckpoint}
        for _, index in ipairs(order) do
            if race.checkpointDistances[index] > race.startDistance then afterGate[#afterGate + 1] = index end
        end
        order = afterGate
    end
    race.sectorCheckpointOrder, race.sectorNumberOfCheckpoint = order, {}
    for position, index in ipairs(order) do race.sectorNumberOfCheckpoint[index] = position end
end

-- Live checkpoint crossing, for the timing panel.
local function onLiveCheckpointCrossing(race, checkpoint, crossingTime)
    if not race.finishCheckpoint then return end
    local liveLap = race.liveLap
    if checkpoint == race.finishCheckpoint or (checkpoint == race.startCheckpoint and not race.rollingStart) then
        if not liveLap.running then
            liveLap.running, liveLap.startTime, liveLap.sectorStartTime, liveLap.sectorTimes = true, crossingTime, crossingTime, {}
        end
        return
    end
    if race.usesOfficialSectors then return end   -- the panel uses the game's official sectors
    if liveLap.running and race.sectorNumberOfCheckpoint[checkpoint] == #liveLap.sectorTimes + 1 then
        liveLap.sectorTimes[#liveLap.sectorTimes + 1] = crossingTime - liveLap.sectorStartTime - bonusData.between(race, liveLap.sectorStartTime, crossingTime)
        liveLap.sectorStartTime = crossingTime
    end
end

-- Colour of a sector: purple if it beats your best, green if it beats the previous lap,
-- amber if it is slower than the previous lap.
local function sectorColor(sectorTime, bestTime, previousTime)
    if not timingPanelLibrary then return nil end
    local colors = timingPanelLibrary.COLORS
    if not bestTime or sectorTime < bestTime - 1e-6 then return colors.best end
    if previousTime then return sectorTime < previousTime and colors.better or colors.worse end
    return colors.text
end

-- Closes a lap that ends at lapEnd and lasts lapTime.
local function closeLap(race, lapEnd, lapTime, isOfficial)
    local lapStart = lapEnd - lapTime
    -- Point-to-point stage: the checkpoint crossed right when the clock starts is the start
    if not race.isClosedCircuit and race.finishCheckpoint and not race.startCheckpoint then
        for _, crossing in ipairs(race.crossings) do
            if crossing.checkpoint ~= race.finishCheckpoint and math.abs(crossing.time - lapStart) < 0.35 then
                race.startDistance = race.checkpointDistances[crossing.checkpoint]
                learnedTracks['start|' .. trackKey(race)] = race.startDistance
                saveLearnedTracks()
                setFinishLine(race, race.finishCheckpoint)
                log(string.format('Salida localizada en el checkpoint %d (%.0f m de la ruta)', crossing.checkpoint, race.startDistance / 100))
                break
            end
        end
    end
    -- Arranque lanzado: tramo de una vuelta en el que el reloj de la vuelta empieza en una puerta,
    -- más de 1 s después del GO. La carrerilla (GO a la puerta) es el S1 y el tiempo es el total.
    local runUp = race.eventZero and (lapStart - race.eventZero)
    local rolling = not race.isClosedCircuit and race.lapCount == 1 and race.startCheckpoint ~= nil and runUp ~= nil and runUp > 1
    local rollingJustLearned = false
    if rolling and not race.rollingStart then
        race.rollingStart, rollingJustLearned = true, true
        learnedTracks['rolling|' .. trackKey(race)] = 1
        saveLearnedTracks()
        setFinishLine(race, race.finishCheckpoint)
        log(string.format('Arranque lanzado: %.3f s de carrerilla hasta la puerta (checkpoint %d)', runUp, race.startCheckpoint))
    end
    -- Arranque lanzado ya aprendido pero sin GO leído: no se puede sacar el total, la vuelta no cuenta para los mejores
    local rollingWithoutGo = race.rollingStart and not rolling
    if rolling then
        -- La carrerilla, con el total del juego si ya lo da (así S1 + resto = total exacto)
        local gameTotal = readProperty(race.raceComponent, 'EventFinishTime')
        if type(gameTotal) == 'number' and gameTotal > lapTime and gameTotal - lapTime < runUp + 1 then runUp = gameTotal - lapTime end
    end
    -- If a checkpoint is crossed twice (crash, respawn) the first crossing counts: the lost time
    -- goes into the next sector.
    local firstCrossings, repeatedCrossings = {}, 0
    for _, crossing in ipairs(race.crossings) do
        if crossing.time > lapStart + 0.25 and crossing.time < lapEnd - 0.25
            and crossing.checkpoint ~= race.finishCheckpoint and crossing.checkpoint ~= race.startCheckpoint then
            if firstCrossings[crossing.checkpoint] then repeatedCrossings = repeatedCrossings + 1 end
            if not firstCrossings[crossing.checkpoint] or crossing.time < firstCrossings[crossing.checkpoint].time then
                firstCrossings[crossing.checkpoint] = crossing
            end
        end
    end
    local crossingsInLap = {}
    for _, crossing in pairs(firstCrossings) do crossingsInLap[#crossingsInLap + 1] = crossing end
    table.sort(crossingsInLap, function(a, b) return a.time < b.time end)
    local resetCount = 0
    for _, resetTime in ipairs(race.resetTimes) do if resetTime > lapStart and resetTime <= lapEnd then resetCount = resetCount + 1 end end
    local expectedCrossings = #race.checkpointDistances - (race.finishCheckpoint and 1 or 0) - (race.startCheckpoint and 1 or 0)
    -- Arranque lanzado: solo cuentan los checkpoints entre la puerta y la meta (el orden empieza por la puerta)
    if rolling then expectedCrossings = #race.sectorCheckpointOrder - 1 end
    local sectorsValid = #crossingsInLap == expectedCrossings and not rollingWithoutGo
    local sectorTimes, previousBoundary = {}, lapStart
    local boundaryTimes = {lapStart}   -- donde empieza y acaba cada sector (para la bonificación)
    if rolling then sectorTimes[1] = runUp; boundaryTimes = {lapStart - runUp, lapStart} end
    for _, crossing in ipairs(crossingsInLap) do
        sectorTimes[#sectorTimes + 1] = crossing.time - previousBoundary; previousBoundary = crossing.time
        boundaryTimes[#boundaryTimes + 1] = crossing.time
    end
    sectorTimes[#sectorTimes + 1] = lapEnd - previousBoundary
    boundaryTimes[#boundaryTimes + 1] = lapEnd
    local sectorCount = expectedCrossings + (rolling and 2 or 1)
    -- Tiempo que cuenta: la vuelta oficial o, con arranque lanzado, el total (carrerilla + vuelta)
    local officialLapTime = lapTime
    if rolling then lapTime = lapTime + runUp end
    -- The game's official sectors, if there are some for this lap and they add up to its time
    local officialLap = not rolling and race.usesOfficialSectors and race.officialSectors and race.officialSectors.completed[#race.officialSectors.completed]
    if officialLap and not officialLap.used and #officialLap.sectorTimes == sectorCount and math.abs(officialLap.time - lapTime) < 0.02 then
        officialLap.used = true
        sectorTimes, sectorsValid = {}, true
        for index, value in ipairs(officialLap.sectorTimes) do sectorTimes[index] = value end
        race.lastSectorSource = 'official'
    else
        race.lastSectorSource = 'detected'
    end
    -- Bonificación (Precisión): la vuelta y cada sector cuentan con lo que te descuentan los puntos
    local lapBonus, sectorBonuses = 0, {}
    if race.usesBonus then
        lapBonus = bonusData.between(race, boundaryTimes[1], lapEnd)
        if #sectorTimes == #boundaryTimes - 1 then
            for index = 1, #sectorTimes do
                sectorBonuses[index] = bonusData.between(race, boundaryTimes[index], boundaryTimes[index + 1])
                sectorTimes[index] = sectorTimes[index] - sectorBonuses[index]
            end
        else
            sectorsValid = false
        end
        lapTime = lapTime - lapBonus
    end
    race.lapNumber = race.lapNumber + 1

    local startLap = isStartLap(race, race.lapNumber)
    local key = bestTimesKey(race, sectorCount, startLap)
    -- References: flying laps (flyingBest) and, on the start lap, its S1 and its time (startBest).
    -- Only the S1 of the start lap is different; the rest of lap 1 counts like any other lap.
    local flyingKey = bestTimesKey(race, sectorCount, false)
    local flyingBest = bestTimes[flyingKey] or {sectors = {}}
    local startBest = startLap and (bestTimes[key] or {sectors = {}}) or nil
    -- (sin «a and b or c»: si aún no hay mejor salida, la vuelta 1 se comparaba con la mejor lanzada)
    local best = {sectors = {}}
    if startLap then best.lap = startBest.lap else best.lap = flyingBest.lap end
    for index = 1, sectorCount do best.sectors[index] = (startLap and index == 1) and startBest.sectors[1] or flyingBest.sectors[index] end
    local sectorParts = {}
    for index, sectorTime in ipairs(sectorTimes) do
        sectorParts[#sectorParts + 1] = string.format('S%d %.3f%s', index, sectorTime, sectorsValid and formatDifference(sectorTime, best.sectors[index]) or '')
    end
    local notes = {}
    if not isOfficial then notes[#notes + 1] = 'tiempo calculado, sin dato oficial' end
    if not sectorsValid then
        notes[#notes + 1] = string.format('sectores no válidos: %d de %d checkpoints', #crossingsInLap, expectedCrossings)
    end
    if resetCount > 0 or repeatedCrossings > 0 then
        notes[#notes + 1] = string.format('incidente: %d retroceso(s), %d checkpoint(s) repetido(s)', resetCount, repeatedCrossings)
    end
    if startLap then notes[#notes + 1] = 'salida: el S1 y el tiempo se comparan con tus salidas' end
    if rolling then notes[#notes + 1] = 'arranque lanzado: vuelta oficial ' .. formatTime(officialLapTime) end
    if rollingWithoutGo then notes[#notes + 1] = 'arranque lanzado sin GO: no cuenta para los mejores' end
    if race.usesBonus then
        -- precisión: el tiempo en pista y la bonificación de la vuelta y de cada sector (y los puntos, a 1,5 s cada uno)
        local points = lapBonus / 1.5
        local bonusParts = {}
        for index, value in ipairs(sectorBonuses) do bonusParts[#bonusParts + 1] = string.format('S%d -%.3f', index, value) end
        notes[#notes + 1] = string.format('precisión: en pista %s, bonificación -%.3f%s%s', formatTime(lapTime + lapBonus), lapBonus,
            math.abs(points - math.floor(points + 0.5)) < 0.01 and string.format(' (%d puntos)', math.floor(points + 0.5)) or '',
            #bonusParts > 0 and (' (' .. table.concat(bonusParts, ', ') .. ')') or '')
    end
    writeSummaryLine(race, string.format('Vuelta %d: %s%s | %s%s', race.lapNumber, formatTime(lapTime), formatDifference(lapTime, best.lap),
        table.concat(sectorParts, ' | '), #notes > 0 and (' [' .. table.concat(notes, '; ') .. ']') or ''))

    -- Result of the lap for the panel (compared with the bests from before)
    local sectorColors, bestSectorTimes = {}, {}
    for index, sectorTime in ipairs(sectorTimes) do
        bestSectorTimes[index] = best.sectors[index]
        sectorColors[index] = sectorsValid and sectorColor(sectorTime, best.sectors[index], race.previousSectorTimes and race.previousSectorTimes[index]) or nil
    end
    race.heldLap = {lapNumber = race.lapNumber, time = lapTime, best = best.lap, sectorTimes = sectorTimes, bestSectorTimes = bestSectorTimes,
        sectorsValid = sectorsValid, previousSectorTimes = race.previousSectorTimes, isStartLap = startLap,
        sectorColors = sectorColors, isNewBest = not best.lap or lapTime < best.lap, showUntil = lapEnd + 5}
    race.lastLap = {time = lapTime, best = best.lap}
    race.lapTimesSum = (race.lapTimesSum or 0) + lapTime
    if not rollingWithoutGo and lapTime >= MIN_LAP_SECONDS and (not race.sessionBestLap or lapTime < race.sessionBestLap) then race.sessionBestLap = lapTime end
    if sectorsValid and not startLap then race.previousSectorTimes = sectorTimes end
    race.panelBestKey = bestTimesKey(race, sectorCount, false)
    -- Ghost: the fastest lap with a complete trace (if there is none yet, the first official lap)
    local oldGhost = ghosts[key]
    if race.heldLap then race.heldLap.ghostLapTime = oldGhost and oldGhost.lapTime or nil end
    -- Arranque lanzado: la referencia del DIF va desde el GO. En la carrera en la que se aprende, el
    -- recorrido se midió desde la puerta y no sirve.
    local ghostStart = rolling and race.eventZero or lapStart
    if isArcadeRace(race) and isOfficial and not rollingJustLearned and not rollingWithoutGo and resetCount == 0 and repeatedCrossings == 0 and lapTime >= MIN_LAP_SECONDS and lapTime <= MAX_LAP_SECONDS
        and (not oldGhost or lapTime < oldGhost.lapTime - 1e-4) then
        local liveStart = race.liveLap and race.liveLap.running and race.liveLap.startTime
        pcall(storeGhost, race, key, ghostStart, lapEnd, lapTime, (liveStart and liveStart >= ghostStart - 0.5 and liveStart < lapEnd) and liveStart or ghostStart)
    end
    local closingLap = race.liveLap
    if closingLap and closingLap.top then
        race.lastLapSpeeds = {top = closingLap.top, minimum = closingLap.minimum}
        if race.sessionBestLap and math.abs(race.sessionBestLap - lapTime) < 1e-4 then race.bestLapSpeeds = race.lastLapSpeeds end
    end
    race.liveLap = {running = true, startTime = lapEnd, sectorStartTime = lapEnd, sectorTimes = {}}
    -- The trace carries on with the points of the new lap (the ones after the finish line)
    local nextLapTrace = {}
    for _, point in ipairs(race.distanceTrace or {}) do if point.time > lapEnd then nextLapTrace[#nextLapTrace + 1] = point end end
    race.distanceTrace, race.traceCrossedFinish = nextLapTrace, false

    local improved = false
    if not rollingWithoutGo and lapTime >= MIN_LAP_SECONDS and lapTime <= MAX_LAP_SECONDS and (not best.lap or lapTime < best.lap) then
        best.lap = lapTime; improved = true
        if startLap then startBest.lap = lapTime else flyingBest.lap = lapTime end
        writeSummaryLine(race, startLap and '  >> Nueva mejor salida' or '  >> Nueva mejor vuelta')
    end
    -- con incidente (retroceso o checkpoint repetido) los sectores no cuentan para los mejores: harían el ideal irreal
    if sectorsValid and resetCount == 0 and repeatedCrossings == 0 then
        for index, sectorTime in ipairs(sectorTimes) do
            local target = (startLap and index == 1) and startBest or flyingBest
            if not target.sectors[index] or sectorTime < target.sectors[index] then
                target.sectors[index] = sectorTime; best.sectors[index] = sectorTime; improved = true
            end
        end
    end
    local idealLap = 0
    for index = 1, sectorCount do
        if not best.sectors[index] then idealLap = nil; break end
        idealLap = idealLap + best.sectors[index]
    end
    if best.lap and idealLap then
        writeSummaryLine(race, string.format('  %sMejor: %s | Ideal (mejores sectores): %s | Margen: %.3f s', startLap and 'Salida · ' or '',
            formatTime(best.lap), formatTime(idealLap), best.lap - idealLap))
    end
    bestTimes[flyingKey] = flyingBest
    if startLap then bestTimes[key] = startBest end
    if improved and isArcadeRace(race) then race.bestTimesChanged = true end   -- se guardan al terminar el evento
    if race.historyPath then
        local sectorsText = {}
        for index, sectorTime in ipairs(sectorTimes) do sectorsText[index] = string.format('%.3f', sectorTime) end
        writeFile(race.historyPath, string.format('%s\tsession %s\tlap %d\t%s\t%s\t%s%s\t%s\n', os.date('%Y-%m-%d %H:%M:%S'),
            race.sessionStamp, race.lapNumber, formatTime(lapTime), sectorsValid and table.concat(sectorsText, ' ') or '-',
            isOfficial and 'official' or 'calculated', (resetCount > 0 or repeatedCrossings > 0) and '\tincident' or '',
            isArcadeRace(race) and race.event.id or 'build'))
    end
    -- Only the crossings of the lap in progress are needed
    local keptCrossings = {}
    for _, crossing in ipairs(race.crossings) do if crossing.time > lapEnd - OFFICIAL_TIME_MATCH_SECONDS then keptCrossings[#keptCrossings + 1] = crossing end end
    race.crossings = keptCrossings
    race.lapStartTime = lapEnd
end

-- Record of each event (event_records.txt): best total, best lap, attempts and target.
-- Format: id \t best_total \t best_lap \t attempts \t target \t date_of_best
local EVENT_RECORDS_PATH = modFile('event_records.txt')
updateEventRecord = function(race, total)
    if not isArcadeRace(race) then return end
    local id = race.event.id
    local rows, order = {}, {}
    local file = io.open(EVENT_RECORDS_PATH, 'r')
    if file then
        for line in file:lines() do
            local key = line:match('^([^\t]+)\t')
            if key then rows[key] = line; order[#order + 1] = key end
        end
        file:close()
    end
    local previous = {}
    if rows[id] then
        local columns = {}
        for value in (rows[id] .. '\t'):gmatch('([^\t]*)\t') do columns[#columns + 1] = value end
        previous = {total = tonumber(columns[2]), lap = tonumber(columns[3]), attempts = tonumber(columns[4]) or 0,
            target = tonumber(columns[5]), date = columns[6]}
    else order[#order + 1] = id end
    local bestLap = previous.lap
    if race.sessionBestLap and (not bestLap or race.sessionBestLap < bestLap) then bestLap = race.sessionBestLap end
    local isNewTotal = total and (not previous.total or total < previous.total)
    rows[id] = table.concat({id, string.format('%.3f', isNewTotal and total or (previous.total or 0)),
        bestLap and string.format('%.3f', bestLap) or '', tostring((previous.attempts or 0) + 1),
        (race.target and string.format('%.3f', race.target.time)) or (previous.target and string.format('%.3f', previous.target)) or '',
        isNewTotal and os.date('%Y-%m-%d %H:%M') or (previous.date or '')}, '\t')
    local output = io.open(EVENT_RECORDS_PATH, 'w')
    if output then
        for _, key in ipairs(order) do output:write(rows[key] .. '\n') end
        output:close()
    end
    if isNewTotal and previous.total then writeSummaryLine(race, string.format('  >> Nuevo récord del evento (antes %s)', formatTime(previous.total))) end
    return previous.total
end

local function averageSpeed(race, fromTime, toTime)
    local sum, count = 0, 0
    for _, sample in ipairs(race.recentSpeeds or {}) do
        if sample.time >= fromTime and sample.time <= toTime then sum = sum + sample.kmh; count = count + 1 end
    end
    return count > 0 and sum / count or nil
end

-- End of the event: the panel stops counting and keeps showing the last lap.
-- Race ghost (0.9.29): your best whole race in each Arcade event (race_ghosts\<event>.txt, written
-- here) or your fastest friend's (race_ghosts\<event>.friend.txt, written by the app). First line:
-- total and pilot; then one point every 0.1 s: seconds since the start, x, y and (yours) z.
local RACE_GHOSTS_FOLDER = MOD_FOLDER .. 'race_ghosts/'
pcall(ensureFolder, RACE_GHOSTS_FOLDER, RACE_GHOSTS_FOLDER .. 'materials.txt')   -- made at load if the app has not made it yet
local GHOST_LIFT = 150   -- cm above the recorded position, so it floats over the track
local function readGhostFile(path, headerOnly)
    local file = io.open(path, 'r'); if not file then return nil end
    local header = {}
    for field in ((file:read('*l') or ''):gsub('\r', '') .. '\t'):gmatch('([^\t]*)\t') do header[#header + 1] = field end
    local total, pilot, clockKind = header[1], header[2], header[3]
    if headerOnly then file:close(); return tonumber(total) and {total = tonumber(total)} or nil end
    local points = {}
    for line in file:lines() do
        local fields, raw = {}, {}
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do raw[#raw + 1] = field; fields[#fields + 1] = tonumber(field) end
        if fields[1] and fields[2] and fields[3] then
            points[#points + 1] = {t = fields[1], x = fields[2], y = fields[3], z = fields[4], yaw = fields[5],
                pitch = fields[6] or (fields[5] and 0), roll = fields[7] or (fields[5] and 0), boost = (raw[8] or ''):match('^%a'),
                trail = raw[9]}   -- columna 9 (W/B/WB/-), nil en los fantasmas anteriores
        end
    end
    file:close()
    if not tonumber(total) or #points < 10 then return nil end
    return {total = tonumber(total), pilot = pilot or '', points = points, clockKind = clockKind or ''}
end
local function saveOwnGhost(race, total)
    if not GHOST_ENABLED or not isArcadeRace(race) or not race.ghostSamples or #race.ghostSamples < 10 then return end
    local path = RACE_GHOSTS_FOLDER .. race.event.id .. '.txt'
    local loosePath = MOD_FOLDER .. 'race_ghost_' .. race.event.id .. '.txt'
    local previous = readGhostFile(path, true) or readGhostFile(loosePath, true)
    if previous and previous.total <= total + 1e-4 then return end
    -- Lua cannot create folders: if race_ghosts does not exist yet (the app makes it the first time it
    -- opens) the ghost goes to the mod folder and the app moves it in.
    if not ensureFolder(RACE_GHOSTS_FOLDER, path) then path = loosePath end
    -- Copia del fantasma que se sustituye, por si hubiera que recuperarlo: <evento>.prev.txt
    if previous then
        local oldFile = io.open(path, 'r') or io.open(loosePath, 'r')
        if oldFile then
            local oldContent = oldFile:read('*a'); oldFile:close()
            if oldContent and oldContent ~= '' then writeFile(path:gsub('%.txt$', '.prev.txt'), oldContent, 'w') end
        end
    end
    -- Times from the game's race timer (0.9.29), so the ghost starts with the GO and not when you
    -- first move (which drifted at the hand-over from the intro to your control)
    local anchor, clockKind = race.eventZero or race.startTime, race.eventZero and 'event' or ''
    local lines = {string.format('%.3f\t\t%s', total, clockKind)}
    for _, sample in ipairs(race.ghostSamples) do
        local line = string.format('%.2f\t%.0f\t%.0f\t%.0f', sample.at - anchor, sample.x, sample.y, sample.z)
        if sample.yaw then line = line .. string.format('\t%.1f\t%.1f\t%.1f\t%s\t%s', sample.yaw, sample.pitch, sample.roll, sample.boost or '', sample.trail or '') end
        lines[#lines + 1] = line
    end
    if writeFile(path, table.concat(lines, '\n') .. '\n', 'w') then log('Fantasma: guardada esta carrera (' .. formatTime(total) .. ') como tu fantasma del evento') end
end

local function finishEvent(race, reason)
    if race.eventEnded then return end
    race.eventEnded = true
    race.liveLap = {running = false, sectorTimes = {}}
    if race.heldLap then race.heldLap.showUntil = math.huge; race.heldLap.isFinal = true end
    log('Fin del evento (' .. reason .. ') tras ' .. race.lapNumber .. ' vueltas')
    local total = readProperty(race.raceComponent, 'EventFinishTime')
    if type(total) ~= 'number' or total <= 0 then total = race.eventTime or race.lapTimesSum end
    race.eventFinalTime = total
    if total then
        local line = 'Evento: ' .. formatTime(total)
        if race.target then
            line = line .. string.format(' | objetivo %s (%s) | %s', formatTime(race.target.time), tostring(race.target.playerName),
                formatSignedDifference(total - race.target.time))
        end
        local readOk, success = pcall(function() return readProperty(race.gameState, 'RaceEventViewModel').bIsSuccess end)
        if readOk and success ~= nil then line = line .. (success and ' | Conseguido' or ' | No conseguido') end
        writeSummaryLine(race, line)
        -- Segunda protección: con vueltas sin completar no se guardan ni récord ni fantasma (salvo que lo diga el juego)
        local incomplete = race.lapCount and race.lapNumber < race.lapCount and reason ~= 'el juego da el evento por terminado'
        local updateOk, previousTotal = false, nil
        if incomplete then
            log(string.format('Evento incompleto (%d de %d vueltas): no se guardan récord, fantasma ni mejores tiempos', race.lapNumber, race.lapCount))
            discardRaceBests(race)
        else
            saveRaceBests(race)
            updateOk, previousTotal = pcall(updateEventRecord, race, total)
            local ghostOk, ghostError = pcall(saveOwnGhost, race, total)
            if not ghostOk then log('Fantasma: no se pudo guardar: ' .. tostring(ghostError)) end
        end
        -- Panel notices: new record (against the mod's and the game's) and #1 beaten
        local previousRecord = updateOk and previousTotal or nil
        local gameRecord = modState.gameRecords and race.event and modState.gameRecords[race.event.id]
        if gameRecord and gameRecord.time and (not previousRecord or gameRecord.time < previousRecord) then previousRecord = gameRecord.time end
        race.notices = {}
        if isArcadeRace(race) and previousRecord and total < previousRecord - 1e-4 then race.notices[#race.notices + 1] = {text = panelTexts.record, color = 'best'} end
        if race.target and total <= race.target.time then race.notices[#race.notices + 1] = {text = panelTexts.beaten, color = 'gain'} end
        if race.historyPath then writeFile(race.historyPath, os.date('%Y-%m-%d %H:%M:%S') .. '\tsession ' .. race.sessionStamp .. '\t' .. line .. '\n') end
    end
end

checkEventEnd = function(race, now)
    local afterFinish = race.afterFinish
    if not afterFinish or race.eventEnded then return end
    -- Speed after the finish line against the speed before: the autopilot goes much slower
    if now >= afterFinish.time + 3 then
        race.afterFinish = nil
        -- Si se sabe cuántas vueltas tiene el evento y faltan, no ha terminado aunque vayas despacio
        -- (en una prueba de 4 vueltas se dio por terminado tras la 1.ª y se guardó media carrera como récord)
        if race.lapCount and race.lapNumber < race.lapCount then return end
        local before, after = afterFinish.speedBefore, averageSpeed(race, afterFinish.time + 1.5, afterFinish.time + 3)
        if before and after and after < AUTOPILOT_RATIO * before then
            finishEvent(race, string.format('velocidad tras la meta %.0f km/h frente a %.0f', after, before))
        end
    end
end

-- First race on a new circuit: the finish is not known until you cross it, so the trace of lap 1
-- is kept as distances along the route (race.routeTrace). When the finish is found it becomes the
-- lap trace, so lap 1 also leaves its ghost and the live difference (DIF) works on lap 1 from the
-- second race on (before, from the third).
local function traceFromRouteTrace(race)
    local routeLength, finishDistance, trace, crossed = race.routeLength, race.checkpointDistances[race.finishCheckpoint], {}, false
    for _, point in ipairs(race.routeTrace or {}) do
        local lapDistance, last = (point.distance - finishDistance + routeLength) % routeLength, trace[#trace]
        if crossed then
            if lapDistance > last.distance and lapDistance < 0.5 * routeLength then trace[#trace + 1] = {time = point.time, distance = lapDistance} end
        elseif not last then
            if lapDistance <= 0.5 * routeLength then trace[1] = {time = point.time, distance = lapDistance} end   -- before: the grid, behind the line
        elseif lapDistance < last.distance - 0.5 * routeLength then
            crossed = true; trace[#trace + 1] = {time = point.time, distance = lapDistance}   -- the line again: lap 2 begins
        elseif lapDistance > last.distance then trace[#trace + 1] = {time = point.time, distance = lapDistance} end
    end
    race.routeTrace = nil
    return trace
end
-- The moment you crossed the line at the start (the panel counts lap 1 from there), from the crossings kept
local function startCrossingTime(race, lapEnd)
    for _, crossing in ipairs(race.crossings) do
        if crossing.checkpoint == race.finishCheckpoint and crossing.time < lapEnd - MIN_LAP_SECONDS then return crossing.time end
    end
    return nil
end

-- Handles the official lap time: the lap ends at the nearest checkpoint crossing.
local function handleOfficialLapTime(race, pending)
    local lapEnd, checkpoint, bestGap = pending.time, nil, OFFICIAL_TIME_MATCH_SECONDS
    for _, crossing in ipairs(race.crossings) do
        local gap = math.abs(crossing.time - pending.time)
        if gap <= bestGap then lapEnd, checkpoint, bestGap = crossing.time, crossing.checkpoint, gap end
    end
    if checkpoint and race.finishCheckpoint ~= checkpoint then
        if race.finishCheckpoint then log('Aviso: la meta parece estar en otro checkpoint (' .. race.finishCheckpoint .. ' -> ' .. checkpoint .. ')') end
        setFinishLine(race, checkpoint)
        learnedTracks['finish|' .. trackKey(race)] = race.checkpointDistances[checkpoint]
        saveLearnedTracks()
        log(string.format('Meta localizada en el checkpoint %d (%.0f m de la ruta)', checkpoint, race.checkpointDistances[checkpoint] / 100))
        -- Lap 1 recorded before knowing the finish: its trace and its start, for its ghost
        if race.isClosedCircuit and race.routeTrace and #(race.distanceTrace or {}) == 0 then
            local ok, trace = pcall(traceFromRouteTrace, race)
            if ok and #trace >= 10 then
                race.distanceTrace, race.traceCrossedFinish = trace, false
                local startTime = startCrossingTime(race, lapEnd)
                if startTime and not (race.liveLap and race.liveLap.running) then
                    race.liveLap = {running = true, startTime = startTime, sectorStartTime = startTime, sectorTimes = {}}
                end
                log(string.format('Vuelta 1 recuperada para el fantasma (%d puntos)', #trace))
            end
        end
        race.routeTrace = nil
    end
    if race.eventEnded then race.eventEnded = false; log('El evento continúa') end
    closeLap(race, lapEnd, pending.lapTime, true)
    if race.lapCount and race.lapNumber >= race.lapCount then
        finishEvent(race, 'última vuelta del evento (' .. race.lapCount .. ')')
    else
        race.afterFinish = {time = lapEnd, speedBefore = averageSpeed(race, lapEnd - 3, lapEnd)}
    end
end

-- Boost of the vehicle at each sample (the 'boost' column): R = ramjet engaged, A = afterburner firing,
-- N = neither, empty = unknown. They come from the vehicle's state: BoostState 4 is the ramjet and
-- AfterburnerState 0 the afterburner (found with the diagnostics of 0.9.25 and checked lap by lap).
local function boostCode(race, pawn)
    if race.vehicleStatePawn ~= pawn then race.vehicleStatePawn, race.vehicleState = pawn, readProperty(pawn, 'VehicleState') end
    local vehicleState = race.vehicleState
    if not isValid(vehicleState) then return '' end
    local boostState, afterburnerState = readProperty(vehicleState, 'BoostState'), readProperty(vehicleState, 'AfterburnerState')
    if boostState == 4 then return 'R' end
    if afterburnerState == 0 then return 'A' end
    if type(boostState) ~= 'number' and type(afterburnerState) ~= 'number' then return '' end
    return 'N'
end

-- In-track ghost test (diagnostics, 0.9.28): in the first race of each session a sphere without collision
-- is created and kept 25 m ahead of you, to see whether the game takes objects created by the mod.
-- The ghost is a plain sphere (an engine basic shape, nothing taken from the game) with no collision,
-- moved every frame along the ghost's trace by the race clock. No keys are bound for it.
local function spawnSphere(pawn, location)
    local actorClass = StaticFindObject('/Script/Engine.StaticMeshActor')
    local mesh = StaticFindObject('/Engine/BasicShapes/Sphere.Sphere')
    if not isValid(mesh) and type(LoadAsset) == 'function' then pcall(function() mesh = LoadAsset('/Engine/BasicShapes/Sphere.Sphere') end) end
    if not isValid(mesh) then mesh = StaticFindObject('/Engine/EngineMeshes/Sphere.Sphere') end
    local worldOk, world = pcall(function() return pawn:GetWorld() end)
    if not worldOk then world = nil end
    local rotation = {Pitch = 0, Yaw = 0, Roll = 0}
    local actor
    if isValid(world) and isValid(actorClass) then
        local ok, result = pcall(function() return world:SpawnActor(actorClass, location, rotation) end)
        if ok and isValid(result) then actor = result end
    end
    if not actor and isValid(actorClass) then
        local transform = {Translation = location, Rotation = {X = 0, Y = 0, Z = 0, W = 1}, Scale3D = {X = 1, Y = 1, Z = 1}}
        local ok, result = pcall(function() return gameplayStatics:BeginDeferredActorSpawnFromClass(pawn, actorClass, transform, 1, nil) end)
        if ok and isValid(result) then pcall(function() gameplayStatics:FinishSpawningActor(result, transform) end); actor = result end
    end
    if not actor then return nil, 'no se pudo crear la esfera' end
    local component = readProperty(actor, 'StaticMeshComponent')
    local failed = {}
    for _, step in ipairs({
        {'movilidad', function() component:SetMobility(2) end},
        {'malla', function() if not isValid(mesh) then error('sin malla') end; component:SetStaticMesh(mesh) end},
        {'sin colisión', function() component:SetCollisionEnabled(0) end},
        {'tamaño', function() actor:SetActorScale3D({X = 1.5, Y = 1.5, Z = 1.5}) end},
    }) do
        local ok = pcall(step[2]); if not ok then failed[#failed + 1] = step[1] end
    end
    return actor, #failed > 0 and ('falló: ' .. table.concat(failed, ', ')) or nil
end
-- Friends' traces carry no height: it is taken from the route (the nearest point on the plane) plus
-- how high your vehicle sits over the route at the start.
local function fillGhostHeights(race, points, pawn)
    local route, start = race.routePoints or {}, toVector(pawn:K2_GetActorLocation())
    local function nearest(x, y, hint)
        local first, last = 1, #route
        if hint then first, last = math.max(1, hint - 40), math.min(#route, hint + 40) end
        local bestIndex, bestDistance = first, math.huge
        for index = first, last do
            local point = route[index]
            local distance = (point.X - x) ^ 2 + (point.Y - y) ^ 2
            if distance < bestDistance then bestIndex, bestDistance = index, distance end
        end
        return bestIndex, bestDistance
    end
    local missing = false
    for _, point in ipairs(points) do if not point.z then missing = true; break end end
    if not missing then return end
    if #route < 2 then for _, point in ipairs(points) do point.z = point.z or start.Z end; return end
    local startIndex = nearest(start.X, start.Y)
    local lift = start.Z - route[startIndex].Z
    local hint
    for _, point in ipairs(points) do
        if not point.z then
            local index, distance = nearest(point.x, point.y, hint)
            if hint and distance > 4e6 then index = nearest(point.x, point.y) end   -- lost (more than 20 m): search the whole route
            hint = index
            point.z = route[index].Z + lift
        end
    end
end
local function removeRaceGhost(race)
    local ghost = race and race.ghost
    if not ghost then return end
    race.ghost = nil
    for _, actor in ipairs(ghost.actors or {ghost.actor}) do pcall(function() if isValid(actor) then actor:K2_DestroyActor() end end) end
end
local hologramMaterial   -- defined below
local function ghostPointAt(points, t)
    local low, high = 1, #points
    if t <= points[1].t then return points[1], points[1], 0 end
    if t >= points[high].t then return points[high], points[high], 0 end
    while high - low > 1 do
        local middle = (low + high) // 2
        if points[middle].t <= t then low = middle else high = middle end
    end
    local from, to = points[low], points[high]
    return from, to, to.t > from.t and (t - from.t) / (to.t - from.t) or 0
end
local function ghostPositionAt(points, t, lift)
    local from, to, fraction = ghostPointAt(points, t)
    return {X = from.x + (to.x - from.x) * fraction, Y = from.y + (to.y - from.y) * fraction, Z = from.z + (to.z - from.z) * fraction + lift}, from
end
-- Estela del fantasma: líneas translúcidas, sobre el último ~1,5 s de su recorrido, que salen de sus
-- propulsores: naranja con la postcombustión (A) y azul con el ramjet (R), de la columna 8 del fantasma.
-- El cuadrado y el freno (columna 9) no se dibujan en pista: se verán en la app.
-- Una línea por propulsor, saliendo de su tobera: el punto VFX_Engine de cada pieza de motor (donde el
-- juego pone su llama). Su posición respecto al centro del vehículo gira con el fantasma (rumbo, cabeceo e
-- inclinación), así que la rasante de canto lleva sus líneas una encima de otra. Si un vehículo no tiene
-- ningún VFX_Engine: la moto, una línea en el centro; el resto, dos a 1,5 m de cada lado.
-- Cada línea es una cinta plana, como una trazada: tramos rectos (cubos aplastados, tumbados en el plano del
-- fantasma) que se tocan justo en sus extremos, sin pasarse (si se alargan, en las curvas se cruzan y forman
-- una X), con un disco plano del mismo ancho en cada vértice para que los giros se vean redondeados.
-- Solo se usa lo que trae el fantasma: sin la columna 8 no hay estela (nada se deduce).
-- Seguridad (el juego se cerró dos veces con la estela antigua, al entrar el ramjet): cada material de color
-- queda puesto toda la carrera en una pieza oculta, para que el juego no lo borre al limpiar memoria, y
-- antes de usar una pieza o un material se comprueba que siga existiendo.
-- Rendimiento (con muchas piezas había tirones): 8 tramos por línea, se actualiza cada 2 fotogramas, y no
-- se dibuja lo que queda detrás de ti.
-- De lejos se ve la línea, para seguir la trazada; entre 100 y 40 m de ti se va afinando y más cerca queda
-- la llama del holograma.
local ghostTrail = {
    PIECES = 8, STEP = 2 / 8,   -- 2 s de recorrido (con 1,5 s se veía corta)
    UPDATE_EVERY_FRAMES = 2,
    ENGINE_SOCKET = 'VFX_Engine',
    -- La línea solo se ve a más de 40 m de ti (aunque no veas al fantasma: si no, se atravesaban sus líneas);
    -- cerca queda la llama en sus toberas. Entre 40 y 100 m se va afinando, para que el extremo
    -- cercano no aparezca cortado de golpe.
    NEAR_DISTANCE = 4000,   -- cm (se probó con 25, 40, 50 y 100 m)
    -- cm en los que la línea pasa de nada a su ancho completo. Con 20 m se notaba un salto: cada tramo mide
    -- unos 25 m a 100 m/s, así que un tramo entero pasaba de golpe de casi nada a todo el ancho
    FADE_DISTANCE = 6000,
    FADE_HIDDEN = 0.05,     -- por debajo de este ancho (en proporción) el tramo no se dibuja
    -- Naranja con brillo doble (valores por encima de 1) para que la postcombustión resalte más que el ramjet
    COLORS = {A = {2, 0.6, 0}, R = {0.2, 0.55, 1}},
    -- Ancho en cm: más ancha si el vehículo tiene un solo propulsor (con 30 y 25 se veía muy fina)
    WIDTH_ONE_ENGINE = 55, WIDTH_SEVERAL_ENGINES = 45,
    THICKNESS_CM = 2,   -- alto de la cinta: lo mínimo para que no tenga volumen
    SCALE_TOLERANCE = 0.03,     -- el tamaño de una pieza solo se actualiza si cambia más de un 3 %
    -- Sin VFX_Engine: posición de cada propulsor respecto al centro, en cm (x adelante, y derecha, z arriba)
    FALLBACK_ONE_ENGINE = {{x = 0, y = 0, z = 0}},
    FALLBACK_TWO_ENGINES = {{x = 0, y = -150, z = 0}, {x = 0, y = 150, z = 0}},
}

-- Ejes del vehículo (adelante, derecha, arriba) para un giro de Unreal (Pitch, Yaw, Roll en grados)
function ghostTrail.axes(pitch, yaw, roll)
    local sp, cp = math.sin(math.rad(pitch)), math.cos(math.rad(pitch))
    local sy, cy = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
    local sr, cr = math.sin(math.rad(roll)), math.cos(math.rad(roll))
    return {X = cp * cy, Y = cp * sy, Z = sp},
        {X = sr * sp * cy - cr * sy, Y = sr * sp * sy + cr * cy, Z = -sr * cp},
        {X = -(cr * sp * cy + sr * sy), Y = cy * sr - cr * sp * sy, Z = cr * cp}
end

-- Giro de Unreal de una pieza plana que apunta en la dirección forward (de largo 1) y tiene su cara hacia up:
-- el eje Y de la pieza queda de lado y el Z, perpendicular a la cinta (como las cuentas de Unreal al pasar de ejes a giro)
function ghostTrail.flatRotation(forward, up)
    local function cross(a, b) return {X = a.Y * b.Z - a.Z * b.Y, Y = a.Z * b.X - a.X * b.Z, Z = a.X * b.Y - a.Y * b.X} end
    local right = cross(up, forward)
    local rightLength = math.sqrt(right.X * right.X + right.Y * right.Y + right.Z * right.Z)
    -- si la cinta va justo hacia arriba o hacia abajo del fantasma, sin giro de lado
    if rightLength < 1e-4 then right = {X = 0, Y = 1, Z = 0} else right = {X = right.X / rightLength, Y = right.Y / rightLength, Z = right.Z / rightLength} end
    local top = cross(forward, right)
    local pitch = math.deg(math.atan(forward.Z, math.sqrt(forward.X * forward.X + forward.Y * forward.Y)))
    local yaw = math.atan(forward.Y, forward.X)
    local sideX, sideY = -math.sin(yaw), math.cos(yaw)
    local roll = math.deg(math.atan(top.X * sideX + top.Y * sideY, right.X * sideX + right.Y * sideY))
    return {Pitch = pitch, Yaw = math.deg(yaw), Roll = roll}
end

-- Un punto del vehículo (x adelante, y derecha, z arriba) llevado al mundo desde center con ese giro
function ghostTrail.toWorld(center, pitch, yaw, roll, offset)
    local forward, right, up = ghostTrail.axes(pitch, yaw, roll)
    return {X = center.X + forward.X * offset.x + right.X * offset.y + up.X * offset.z,
        Y = center.Y + forward.Y * offset.x + right.Y * offset.y + up.Y * offset.z,
        Z = center.Z + forward.Z * offset.x + right.Z * offset.y + up.Z * offset.z}
end

-- Toberas de tu vehículo: el VFX_Engine de cada pieza que copió el holograma, respecto al centro del vehículo
function ghostTrail.engineOffsets(ghost, pawn)
    local offsets = {}
    local center, rotation = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
    local forward, right, up = ghostTrail.axes(rotation.Pitch, rotation.Yaw, rotation.Roll)
    local socket = FName(ghostTrail.ENGINE_SOCKET)
    for _, part in ipairs(ghost.parts or {}) do
        local source = part.source
        if isValid(source) then
            local hasSocket = false
            pcall(function() hasSocket = source:DoesSocketExist(socket) end)
            local where
            if hasSocket then pcall(function() where = source:GetSocketLocation(socket) end) end
            if where then
                local dx, dy, dz = where.X - center.X, where.Y - center.Y, where.Z - center.Z
                offsets[#offsets + 1] = {x = dx * forward.X + dy * forward.Y + dz * forward.Z,
                    y = dx * right.X + dy * right.Y + dz * right.Z, z = dx * up.X + dy * up.Y + dz * up.Z}
            end
        end
    end
    return offsets
end

-- Si el fantasma trae el motor (columna 8)
function ghostTrail.hasMotorData(points)
    for _, point in ipairs(points) do
        if point.boost then return true end
    end
    return false
end

-- Color en un punto del fantasma, o nil si ahí no usaba ni postcombustión ni ramjet
function ghostTrail.colorAt(point)
    if point.boost == 'A' or point.boost == 'R' then return point.boost end
    return nil
end

-- Una forma básica del motor (cilindro, esfera...), o nil si no está
function ghostTrail.findShape(name)
    local path = '/Engine/BasicShapes/' .. name .. '.' .. name
    local shape = StaticFindObject(path)
    if not isValid(shape) and type(LoadAsset) == 'function' then pcall(function() shape = LoadAsset(path) end) end
    return isValid(shape) and shape or nil
end

-- Una pieza de la estela: una forma sin colisión, oculta y lejos, hasta que se use
-- Menos trabajo de dibujo para las piezas del fantasma (holograma, llama y estela): sin sombra (el juego
-- las volvía a dibujar para las sombras) y sin calcomanías del escenario encima
function ghostTrail.lightRendering(component)
    pcall(function() component:SetCastShadow(false) end)
    pcall(function() component:SetReceivesDecals(false) end)
end

function ghostTrail.spawnPiece(world, actorClass, shape, where)
    local actor = world:SpawnActor(actorClass, {X = where.X, Y = where.Y, Z = where.Z - 10000}, {Pitch = 0, Yaw = 0, Roll = 0})
    if not isValid(actor) then return nil end
    local component = readProperty(actor, 'StaticMeshComponent')
    if not isValid(component) then pcall(function() actor:K2_DestroyActor() end); return nil end
    pcall(function() component:SetMobility(2) end)
    pcall(function() component:SetStaticMesh(shape) end)
    pcall(function() component:SetCollisionEnabled(0) end)
    ghostTrail.lightRendering(component)
    pcall(function() actor:SetActorHiddenInGame(true) end)
    return {actor = actor, component = component, shown = false}
end

-- Los materiales naranja (A) y azul (R) de la estela o de la llama (use: 'trail' o 'flame'): se crean una vez
-- y cada uno queda puesto toda la carrera en una pieza oculta que no se mueve (para que el juego no lo borre).
-- La estela tiene siempre la misma opacidad (en la app solo se activa o desactiva); la llama sigue la
-- transparencia elegida.
-- glass (opcional): el cristal que hay que usar; highlights (opcional): el brillo de cada color
function ghostTrail.boostMaterials(ghost, world, actorClass, shape, where, use, colors, glass, highlights)
    ghost.boostMaterials = ghost.boostMaterials or {}
    local key = use .. (glass or '')
    if ghost.boostMaterials[key] then return ghost.boostMaterials[key] end
    local materials = {}
    ghost.actors = ghost.actors or {ghost.actor}
    for _, color in ipairs({'A', 'R'}) do
        local rgb = (colors or ghostTrail.COLORS)[color]
        local material = hologramMaterial(world, {R = rgb[1], G = rgb[2], B = rgb[3]}, use, {glass = glass, highlight = highlights and highlights[color]})
        local holder = isValid(material) and ghostTrail.spawnPiece(world, actorClass, shape, where) or nil
        if holder then
            pcall(function() holder.component:SetMaterial(0, material) end)
            ghost.actors[#ghost.actors + 1] = holder.actor
            materials[color] = material
        end
    end
    ghost.boostMaterials[key] = materials
    return materials
end

function ghostTrail.spawn(ghost, pawn, world, vehicleType)
    if not ghostTrail.hasMotorData(ghost.points) then return 'sin estela (el fantasma no trae datos de postcombustión ni ramjet)' end
    local actorClass = StaticFindObject('/Script/Engine.StaticMeshActor')
    -- Una cinta plana, como una trazada (el cilindro daba volumen): tramos con el cubo aplastado y, en los
    -- vértices, el cilindro aplastado como un disco (si no está, sin vértices)
    local segmentShape = ghostTrail.findShape('Cube')
    local jointShape = ghostTrail.findShape('Cylinder')
    if not (isValid(actorClass) and segmentShape and isValid(world)) then return 'sin estela (falta la pieza básica)' end
    -- De dónde sale cada línea
    local engines, engineSource = {}, 'VFX_Engine'
    pcall(function() engines = ghostTrail.engineOffsets(ghost, pawn) end)
    if #engines == 0 then
        engines = vehicleType == 'BIKE' and ghostTrail.FALLBACK_ONE_ENGINE or ghostTrail.FALLBACK_TWO_ENGINES
        engineSource = 'sin VFX_Engine, posición fija'
    end
    local width = #engines == 1 and ghostTrail.WIDTH_ONE_ENGINE or ghostTrail.WIDTH_SEVERAL_ENGINES
    local where = pawn:K2_GetActorLocation()
    ghost.actors = ghost.actors or {ghost.actor}
    local trail = {materials = ghostTrail.boostMaterials(ghost, world, actorClass, segmentShape, where, 'trail'), lanes = {}}
    if not next(trail.materials) then return 'sin estela (sin material)' end
    local pieceCount = 0
    -- Cada tramo y cada vértice tiene una pieza de cada color, con su material puesto desde el principio:
    -- cambiar el material en carrera daba tirones (el color cambia a lo largo de la línea a cada momento)
    local function addSlot(shape)
        if not shape then return nil end
        local slot = {}
        for color, material in pairs(trail.materials) do
            local piece = ghostTrail.spawnPiece(world, actorClass, shape, where)
            if piece then
                pcall(function() piece.component:SetMaterial(0, material) end)
                ghost.actors[#ghost.actors + 1] = piece.actor
                pieceCount = pieceCount + 1
                slot[color] = piece
            end
        end
        return next(slot) and slot or nil
    end
    local positions = {}
    for _, engine in ipairs(engines) do
        local segments, joints = {}, {}
        for index = 1, ghostTrail.PIECES do
            segments[index] = addSlot(segmentShape)
            joints[index] = addSlot(jointShape)
        end
        trail.lanes[#trail.lanes + 1] = {offset = engine, width = width, segments = segments, joints = joints}
        positions[#positions + 1] = string.format('%.0f/%.0f/%.0f', engine.x, engine.y, engine.z)
    end
    ghost.trail = trail
    return string.format('estela de %d línea(s) y %d piezas (%s; toberas %s en %s; vértices %s)', #trail.lanes, pieceCount,
        vehicleType or 'vehículo desconocido', engineSource, table.concat(positions, ', '), jointShape and 'redondeados' or 'sin redondear')
end

-- Oculta una pieza (solo llama al juego si estaba a la vista y sigue existiendo)
function ghostTrail.hidePiece(piece)
    if piece and piece.shown then
        piece.shown = false
        if isValid(piece.actor) then pcall(function() piece.actor:SetActorHiddenInGame(true) end) end
    end
end

-- Oculta las piezas de un tramo o vértice (una por color)
function ghostTrail.hideSlot(slot)
    if not slot then return end
    for _, piece in pairs(slot) do ghostTrail.hidePiece(piece) end
end

function ghostTrail.hideAll(trail)
    for _, lane in ipairs(trail.lanes) do
        for index = 1, ghostTrail.PIECES do
            ghostTrail.hideSlot(lane.segments[index])
            ghostTrail.hideSlot(lane.joints[index])
        end
    end
end

-- Mover sin perder memoria: K2_SetActorLocationAndRotation y parecidas devuelven un resultado de choque
-- (FHitResult) que UE4SS guarda para siempre en su registro, uno por llamada (era la fuga: uno por
-- fotograma con el fantasma). K2_TeleportTo mueve igual y no devuelve nada de eso. Si no funciona en este
-- juego, o el juego rechaza el movimiento, se usa la de antes para no dejar el fantasma quieto.
function ghostTrail.moveActor(actor, location, rotation)
    if not ghostTrail.teleportBroken then
        local ok, moved = pcall(actor.K2_TeleportTo, actor, location, rotation)   -- igual que actor:K2_TeleportTo(...), sin crear una función en cada llamada
        if ok and moved ~= false then return end
        if not ok then
            ghostTrail.teleportBroken = true
            log('Fantasma: K2_TeleportTo no funciona (' .. tostring(moved) .. '); se mueve como antes (pierde memoria)')
        else
            -- cada rechazo deja un resultado de choque en memoria: se cuentan para ver si son muchos
            ghostTrail.teleportRefusals = (ghostTrail.teleportRefusals or 0) + 1
            if ghostTrail.teleportRefusals == 1 or ghostTrail.teleportRefusals % 1000 == 0 then
                log(string.format('Fantasma: el juego rechazó %d K2_TeleportTo en esta sesión (esas veces se mueve como antes)', ghostTrail.teleportRefusals))
            end
        end
    end
    actor:K2_SetActorLocationAndRotation(location, rotation, false, {}, true)
end

-- Coloca y muestra la pieza del color pedido de un tramo o vértice, y oculta la del otro color.
-- El tamaño solo se manda al juego si cambia más de SCALE_TOLERANCE (es lo que más se repite).
function ghostTrail.placeSlot(slot, color, location, rotation, scale)
    local piece = slot and slot[color]
    if not (piece and isValid(piece.actor)) then ghostTrail.hideSlot(slot); return end
    for otherColor, other in pairs(slot) do
        if otherColor ~= color then ghostTrail.hidePiece(other) end
    end
    ghostTrail.moveActor(piece.actor, location, rotation)
    local last, tolerance = piece.scale, ghostTrail.SCALE_TOLERANCE
    if not last or math.abs(last.X - scale.X) > last.X * tolerance or math.abs(last.Y - scale.Y) > last.Y * tolerance then
        piece.actor:SetActorScale3D(scale)
        piece.scale = scale
    end
    if not piece.shown then piece.shown = true; piece.actor:SetActorHiddenInGame(false) end
end

-- Si un punto queda por delante de ti (según hacia dónde vas); sin datos, cuenta como delante
function ghostTrail.isAheadOfYou(race, location)
    local position, forward = race and race.lastPosition, race and race.playerForward
    if not position or not forward then return true end
    return (location.X - position.X) * forward.X + (location.Y - position.Y) * forward.Y > 0
end

-- Distancia de un punto a ti, en cm; sin datos, muy lejos
function ghostTrail.distanceToYou(race, location)
    local position = race and race.lastPosition
    if not position then return math.huge end
    local dx, dy, dz = location.X - position.X, location.Y - position.Y, location.Z - position.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Ancho (en proporción) según la distancia: va de 0 a 1 en los FADE_DISTANCE cm después de NEAR_DISTANCE,
-- en curva suave (empieza y acaba despacio) para que no se note dónde empieza ni dónde acaba
function ghostTrail.fadeFactor(race, location)
    local beyond = ghostTrail.distanceToYou(race, location) - ghostTrail.NEAR_DISTANCE
    local progress = math.max(0, math.min(1, beyond / ghostTrail.FADE_DISTANCE))
    return progress * progress * (3 - 2 * progress)
end

-- Dónde está una tobera del fantasma en el instante t: su centro más la posición de la tobera girada con él
function ghostTrail.enginePosition(ghost, t, offset)
    local center = ghostPositionAt(ghost.points, t, ghost.lift)
    local point = ghostPointAt(ghost.points, t)
    return ghostTrail.toWorld(center, point.pitch or 0, point.yaw or 0, point.roll or 0, offset)
end

-- Cada tramo cubre STEP segundos del recorrido reciente del fantasma: va del punto "older" al "newer",
-- y en el "newer" (el más cercano al fantasma) lleva su disco de vértice
function ghostTrail.draw(ghost, elapsed, race)
    local trail, firstTime = ghost.trail, ghost.points[1].t
    trail.frame = (trail.frame or 0) + 1
    if trail.frame % ghostTrail.UPDATE_EVERY_FRAMES ~= 0 then return end
    -- Si el fantasma va por detrás de ti, su estela también: no se calcula nada
    if not ghostTrail.isAheadOfYou(race, ghostPositionAt(ghost.points, elapsed, ghost.lift)) then ghostTrail.hideAll(trail); return end
    for index = 1, ghostTrail.PIECES do
        local newer, older = elapsed - (index - 1) * ghostTrail.STEP, elapsed - index * ghostTrail.STEP
        local point = older > firstTime and ghostPointAt(ghost.points, newer) or nil
        local color = point and ghostTrail.colorAt(point)
        local material = color and trail.materials[color]
        local thinner = 1 - 0.6 * (index - 0.5) / ghostTrail.PIECES   -- más fina cuanto más atrás (en el centro del tramo)
        for _, lane in ipairs(trail.lanes) do
            local segment, joint = lane.segments[index], lane.joints[index]
            local start, finish, middle, fade
            if material and isValid(material) then
                start = ghostTrail.enginePosition(ghost, older, lane.offset)
                finish = ghostTrail.enginePosition(ghost, newer, lane.offset)
                middle = {X = (start.X + finish.X) / 2, Y = (start.Y + finish.Y) / 2, Z = (start.Z + finish.Z) / 2}
                -- La línea se afina poco a poco al acercarse a ti (y con el fantasma a la vista deja paso a su llama).
                -- También sin ver al fantasma: la cola de la estela (2 s) llega hasta ti si vas a menos de 2 s de él,
                -- y se atravesaban las líneas a todo su ancho
                fade = ghostTrail.fadeFactor(race, middle)
                -- detrás de ti no se ve; demasiado fina, tampoco
                if not ghostTrail.isAheadOfYou(race, finish) or fade < ghostTrail.FADE_HIDDEN then start, finish = nil, nil end
            end
            local dx, dy, dz = 0, 0, 0
            if start then dx, dy, dz = finish.X - start.X, finish.Y - start.Y, finish.Z - start.Z end
            local length = math.sqrt(dx * dx + dy * dy + dz * dz)
            if not start or length <= 1 then
                ghostTrail.hideSlot(segment)
                ghostTrail.hideSlot(joint)
            else
                local size, flat = lane.width * thinner * fade / 100, ghostTrail.THICKNESS_CM / 100
                -- La cinta va de start a finish, tumbada en el plano del fantasma (su "arriba" en ese momento)
                local _, _, up = ghostTrail.axes(point.pitch or 0, point.yaw or 0, point.roll or 0)
                local rotation = ghostTrail.flatRotation({X = dx / length, Y = dy / length, Z = dz / length}, up)
                ghostTrail.placeSlot(segment, color, middle, rotation, {X = length / 100, Y = size, Z = flat})
                -- Vértice: un disco plano del mismo ancho en el extremo más cercano al fantasma (redondea las curvas)
                ghostTrail.placeSlot(joint, color, finish, rotation, {X = size, Y = size, Z = flat})
            end
        end
    end
end

-- Llama del fantasma: las formas de la llama de tu vehículo (EngineFlareMesh y EngineRamjetMesh, que cambian
-- con el modelo) puestas como piezas propias en el VFX_Engine de cada motor del holograma, con el naranja y
-- el azul de la estela. Con A se ve el destello naranja, con R la forma del ramjet en azul, y con N nada.
-- No usa el efecto del juego (NS_RaceEngine): su color depende de valores globales que mueve tu vehículo, y la
-- llama del fantasma acababa pintándose según tú. Las mallas y el tamaño se leen una sola vez, al crear el
-- fantasma, de la llama de tu vehículo; en carrera solo cuenta la columna 8 del fantasma.
-- Van enganchadas a la tobera del holograma: se mueven con él sin coste; solo se muestran u ocultan al cambiar.
-- De cerca se ve la llama; de lejos, la línea de la estela.
local ghostFlame = {
    ENGINE_EFFECT = 'NS_RaceEngine',
    ENGINE_SOCKET = 'VFX_Engine',
    SNAP_TO_TARGET = 2,   -- EAttachmentRule: pegada al punto del motor
    -- Las piezas de la llama: con qué boost se ven, qué forma usan y cuánto se estiran.
    -- Las formas son pequeñas (un disco de 1 m y un anillo de 50 cm): el efecto del juego las estira hacia atrás.
    -- Aquí se estiran a lo largo del eje X del punto del motor (stretch), se ensanchan para cubrir el motor
    -- (width) y se desplazan hacia atrás para empezar en la tobera. El ramjet es un anillo: con él va también
    -- el disco del destello en azul, para que no se vea un agujero negro en el centro.
    -- invert: la forma tiene la parte ancha en el otro lado (el destello va al revés que el anillo del ramjet)
    -- pull: parte de su media longitud que se acerca a la tobera (para empalmar con la pieza de delante)
    PIECES = {
        -- Postcombustión: como el ramjet (el disco solo apenas se veía sobre el cristal), en naranja y un 15 % más pequeña
        {boost = 'A', shape = 'EngineRamjetMesh', stretch = 5, width = 1.5},
        {boost = 'A', shape = 'EngineFlareMesh', stretch = 5, width = 1.3, invert = true, pull = 0.5},
        -- base en la tobera para tapar el hueco desde detrás: la esfera básica del motor aplastada como un disco
        -- (la forma del destello también es un aro hueco y no tapaba nada); a la mitad de ancho, se veía grande
        {boost = 'A', basicShape = 'Sphere', stretch = 0.4, width = 0.7},
        {boost = 'R', shape = 'EngineRamjetMesh', stretch = 6, width = 1.8},
        {boost = 'R', shape = 'EngineFlareMesh', stretch = 6, width = 1.6, invert = true, pull = 0.5},   -- quedaba un hueco con el anillo
        {boost = 'R', basicShape = 'Sphere', stretch = 0.4, width = 0.85},   -- base maciza en la tobera, a la mitad (1,7 era grande)
    },
    -- Colores de la llama, más claros que los de la estela (el cristal los oscurece). El naranja necesita el
    -- doble de brillo que el azul para verse igual de vivo: el cristal filtra el fondo (cielo y pista, más bien
    -- azulados o grises) y con naranja deja pasar poca luz.
    -- El naranja, dentro de 0 a 1: con valores mayores el juego recorta rojo y verde al máximo y salía amarillo
    -- o verde oliva. El brillo se da aparte, con HIGHLIGHT (Highlight Color Multiplier del cristal).
    -- Con {1; 0,6; 0,15} y el mismo brillo que el azul, el naranja seguía oscuro: más puro y con el doble de brillo
    COLORS = {A = {1, 0.5, 0.05}, R = {0.7, 1.3, 2.5}},   -- con 0,4 de verde salía casi rojo
    HIGHLIGHT = {A = 16, R = 8},
    -- Cristal del juego de cada boost, elegido comparándolos en pista (2026-11-02): la postcombustión se ve
    -- mejor con Pepper y el ramjet con Potato. Descartado MI_Onion_Glass: solo tiene color en el borde
    -- (Color Edge) y se veía más oscuro. Si falta uno, se usa el cristal de siempre.
    GLASS = {A = 'MI_Pepper_02_Glass', R = 'MI_Potato_Glass'},
    -- Hacia dónde sale el chorro se calcula en cada motor: el eje X de VFX_Engine apunta hacia el morro
    -- (la llama salía delante del motor), pero se compara con el vehículo por si algún modelo lo tiene al revés.
    OUTWARD_CM = 0,   -- desplazamiento extra hacia fuera de la tobera, por si hay que afinar
    -- Tipo de cada valor de usuario del efecto (lo que no está aquí y no es malla, es sí/no)
    INTEGERS = {VehicleType = true, VehicleIndex = true, EngineGear = true, RamjetMode = true},
    FLOATS = {EngineSize = true, MinRadius = true, MaxRadius = true, NozzleDilationScale = true},
}

-- Tipo de un valor por su nombre: malla, entero, decimal o sí/no
function ghostFlame.kindOf(shortName)
    if shortName:find('Mesh', 1, true) then return 'object' end
    if ghostFlame.INTEGERS[shortName] then return 'integer' end
    if ghostFlame.FLOATS[shortName] then return 'float' end
    return 'bool'
end

-- Valores de usuario de un efecto, leídos de donde el efecto los guarda (OverrideParameters):
-- la lista de nombres con su posición, los bytes de los números y la lista de objetos (mallas)
function ghostFlame.readParameters(component)
    local store = readProperty(component, 'OverrideParameters')
    if not store then return {}, 'sin OverrideParameters' end
    local bytes, objects, parameters = {}, {}, {}
    pcall(function() store.ParameterData:ForEach(function(_, element) bytes[#bytes + 1] = element:get() end) end)
    pcall(function() store.UObjects:ForEach(function(_, element) objects[#objects + 1] = element:get() end) end)
    pcall(function()
        store.SortedParameterOffsets:ForEach(function(_, element)
            local entry, name, offset = element:get(), '?', nil
            pcall(function() name = entry.Name:ToString() end)
            pcall(function() offset = entry.Offset end)
            parameters[#parameters + 1] = {name = name, short = name:gsub('^User%.', ''), offset = offset}
        end)
    end)
    for _, parameter in ipairs(parameters) do
        parameter.kind = ghostFlame.kindOf(parameter.short)
        local offset = parameter.offset
        if parameter.kind == 'object' then
            parameter.value = offset and objects[offset + 1]
        elseif offset and bytes[offset + 4] then
            local packed = string.char(bytes[offset + 1], bytes[offset + 2], bytes[offset + 3], bytes[offset + 4])
            parameter.value = parameter.kind == 'float' and string.unpack('<f', packed) or string.unpack('<i4', packed)
        end
    end
    return parameters, string.format('%d valores, %d bytes, %d objetos', #parameters, #bytes, #objects)
end

-- Tamaño de una malla (medio ancho en x, y, z), para el log: sirve para ajustar orientación y escala
function ghostFlame.meshSize(mesh)
    local text = '?'
    pcall(function()
        local extent = mesh:GetBounds().BoxExtent
        text = string.format('%.0fx%.0fx%.0f', extent.X, extent.Y, extent.Z)
    end)
    return text
end

function ghostFlame.spawn(ghost, pawn)
    if not ghostTrail.hasMotorData(ghost.points) then return 'sin llama (el fantasma no trae datos de postcombustión ni ramjet)' end
    local actorClass = StaticFindObject('/Script/Engine.StaticMeshActor')
    local world
    pcall(function() world = pawn:GetWorld() end)
    if not (isValid(actorClass) and isValid(world)) then return 'sin llama (falta la pieza básica)' end
    local where = pawn:K2_GetActorLocation()
    -- El material de cada boost, con su cristal (si no está en esta partida, el cristal de siempre)
    local materials, glassNotes = {}, {}
    for _, boost in ipairs({'A', 'R'}) do
        local glass = ghostFlame.GLASS[boost]
        local material = ghostTrail.boostMaterials(ghost, world, actorClass, ghostTrail.findShape('Cube'), where, 'flame', ghostFlame.COLORS, glass, ghostFlame.HIGHLIGHT)[boost]
        if not material then
            glass = 'cristal de siempre'
            material = ghostTrail.boostMaterials(ghost, world, actorClass, ghostTrail.findShape('Cube'), where, 'flame', ghostFlame.COLORS, nil, ghostFlame.HIGHLIGHT)[boost]
        end
        if material then materials[boost] = material; glassNotes[#glassNotes + 1] = boost .. ' ' .. glass end
    end
    if not next(materials) then return 'sin llama (sin material)' end
    local socket = FName(ghostFlame.ENGINE_SOCKET)
    local engines, notes = {}, {}
    for _, part in ipairs(ghost.parts or {}) do
        local copyComponent = isValid(part.copy) and readProperty(part.copy, 'StaticMeshComponent')
        local hasSocket = false
        if isValid(copyComponent) then pcall(function() hasSocket = copyComponent:DoesSocketExist(socket) end) end
        local source = hasSocket and ghostFlame.findSourceFlame(pawn, part.source) or nil
        if source then
            -- Las formas y el tamaño de la llama de ese motor de tu vehículo, leídos una vez
            local meshes, size = {}, 1
            for _, parameter in ipairs(ghostFlame.readParameters(source)) do
                if parameter.short == 'EngineSize' and type(parameter.value) == 'number' and parameter.value > 0 then size = parameter.value end
                if parameter.kind == 'object' and isValid(parameter.value) then meshes[parameter.short] = parameter.value end
            end
            -- Signo del eje X del punto del motor hacia fuera de la tobera (hacia atrás del vehículo)
            local outwardSign = -1
            pcall(function()
                local socketRotation, pawnRotation = copyComponent:GetSocketRotation(socket), pawn:K2_GetActorRotation()
                local socketForward = ghostTrail.axes(socketRotation.Pitch, socketRotation.Yaw, socketRotation.Roll)
                local vehicleForward = ghostTrail.axes(pawnRotation.Pitch, pawnRotation.Yaw, pawnRotation.Roll)
                local dot = socketForward.X * vehicleForward.X + socketForward.Y * vehicleForward.Y + socketForward.Z * vehicleForward.Z
                outwardSign = dot > 0 and -1 or 1
            end)
            local engine = {pieces = {}}
            for _, spec in ipairs(ghostFlame.PIECES) do
                local mesh = spec.basicShape and ghostTrail.findShape(spec.basicShape) or meshes[spec.shape]
                local piece = mesh and materials[spec.boost] and ghostTrail.spawnPiece(world, actorClass, mesh, where)
                if piece then
                    pcall(function() piece.component:SetMaterial(0, materials[spec.boost]) end)
                    pcall(function() piece.actor:K2_AttachToComponent(copyComponent, socket, ghostFlame.SNAP_TO_TARGET, ghostFlame.SNAP_TO_TARGET, ghostFlame.SNAP_TO_TARGET, false) end)
                    local length, width = size * spec.stretch, size * spec.width
                    pcall(function() piece.actor:SetActorRelativeScale3D({X = length, Y = width, Z = width}) end)
                    -- Media pieza hacia atrás, para que empiece en la tobera
                    local halfLength = 0
                    pcall(function() halfLength = mesh:GetBounds().BoxExtent.X * length end)
                    local outward = halfLength * (1 - (spec.pull or 0)) + ghostFlame.OUTWARD_CM * size
                    pcall(function() piece.actor:K2_SetActorRelativeLocation({X = outward * outwardSign, Y = 0, Z = 0}, false, {}, true) end)
                    -- Estirada, la forma es como una trompeta con la parte ancha en su lado +X: se gira 180 grados
                    -- solo si ese lado quedaría lejos de la tobera, para que la parte ancha salga del motor
                    local flip = outwardSign > 0
                    if spec.invert then flip = not flip end
                    if flip then pcall(function() piece.actor:K2_SetActorRelativeRotation({Pitch = 0, Yaw = 180, Roll = 0}, false, {}, true) end) end
                    piece.boost = spec.boost
                    pcall(function() piece.component:SetVisibility(false, false) end)   -- oculta hasta que toque su boost
                    engine.pieces[#engine.pieces + 1] = piece
                    ghost.actors[#ghost.actors + 1] = piece.actor
                    notes[#notes + 1] = string.format('%s %s (%s, tamaño %.2f, eje %s)', spec.boost, fullName(mesh):match('([^%.]+)$') or '?', ghostFlame.meshSize(mesh), size,
                        outwardSign < 0 and 'hacia el morro' or 'hacia atrás')
                end
            end
            if next(engine.pieces) then engines[#engines + 1] = engine end
        end
    end
    if #engines == 0 then return 'sin llama (no se encontró la llama de tus motores)' end
    ghost.flameEngines = engines
    return string.format('llama propia en %d motor(es) (cristales: %s): %s', #engines, table.concat(glassNotes, ', '), table.concat(notes, ', '))
end

-- Cada fotograma: se ve la forma del boost que usa el fantasma (solo se toca al cambiar)
function ghostFlame.update(ghost, elapsed)
    local point = ghostPointAt(ghost.points, elapsed)
    local boost = point and point.boost
    if boost ~= 'A' and boost ~= 'R' then boost = 'N' end
    if ghost.flameBoost == boost then return end
    ghost.flameBoost = boost
    for _, engine in ipairs(ghost.flameEngines) do
        for _, piece in ipairs(engine.pieces) do
            local visible = piece.boost == boost
            -- Se oculta el actor y también su malla: enganchada al holograma, ocultar solo el actor no siempre basta
            if isValid(piece.actor) then pcall(function() piece.actor:SetActorHiddenInGame(not visible) end) end
            if isValid(piece.component) then pcall(function() piece.component:SetVisibility(visible, false) end) end
            piece.shown = visible
        end
    end
end

-- Llama del juego en el fantasma (prueba, ghost_flame_mode = game o both): el efecto NS_RaceEngine en cada
-- tobera del holograma, con la configuración de tu llama y sus interruptores movidos por la columna 8.
-- Antes fallaba el color porque se copiaba tu VehicleIndex (el 0): cada vehículo de la carrera tiene el suyo
-- (la IA usa 1, 2, 3...) y la llama lee parte de su estado de una tabla común por ese número, así que la del
-- fantasma se pintaba según tú. Aquí se usa un número que no tenga nadie (hay carreras de 12 vehículos).
ghostFlame.GAME_FLAME_INDEX = 15
-- Tiempos de la secuencia del juego, en segundos (medidos con tu llama y con la de la IA)
ghostFlame.PULSE_SECONDS, ghostFlame.RAMJET_ENGAGE_SECONDS, ghostFlame.RAMJET_COOLDOWN_SECONDS = 0.27, 0.55, 1.0
-- Con VehicleIndex libre, el azul del ramjet solo aparecía durante el arranque (RamjetEngaging) y luego volvía el
-- naranja (el color mantenido sale de la tabla común del juego). Prueba: mantener RamjetEngaging todo el ramjet.
ghostFlame.HOLD_RAMJET_ENGAGING = true

-- Pone un valor en una llama, con la función que corresponde a su tipo
function ghostFlame.setValue(flame, shortName, kind, value)
    local name = FName(shortName)
    if kind == 'object' then
        if not isValid(value) then return end
        local done = pcall(function() flame:SetVariableStaticMesh(name, value) end)
        if not done then pcall(function() flame:SetVariableObject(name, value) end) end
    elseif type(value) ~= 'number' then
        return
    elseif kind == 'integer' then pcall(function() flame:SetVariableInt(name, value) end)
    elseif kind == 'float' then pcall(function() flame:SetVariableFloat(name, value) end)
    else pcall(function() flame:SetVariableBool(name, value ~= 0) end)
    end
end

function ghostFlame.spawnGameFlames(ghost, pawn)
    if not ghostTrail.hasMotorData(ghost.points) then return 'sin llama del juego (el fantasma no trae datos de postcombustión ni ramjet)' end
    local library = StaticFindObject('/Script/Niagara.Default__NiagaraFunctionLibrary')
    if not isValid(library) then return 'sin llama del juego (no está la librería de efectos)' end
    local socket = FName(ghostFlame.ENGINE_SOCKET)
    local flames = {}
    for _, part in ipairs(ghost.parts or {}) do
        local copyComponent = isValid(part.copy) and readProperty(part.copy, 'StaticMeshComponent')
        local hasSocket = false
        if isValid(copyComponent) then pcall(function() hasSocket = copyComponent:DoesSocketExist(socket) end) end
        local source = hasSocket and ghostFlame.findSourceFlame(pawn, part.source) or nil
        local system = source and readProperty(source, 'Asset')
        if isValid(system) then
            local parameters = ghostFlame.readParameters(source)
            local flame
            pcall(function()
                flame = library:SpawnSystemAttached(system, copyComponent, socket, {X = 0, Y = 0, Z = 0}, {Pitch = 0, Yaw = 0, Roll = 0},
                    ghostFlame.SNAP_TO_TARGET, false, true, 0, false)
            end)
            if isValid(flame) then
                for _, parameter in ipairs(parameters) do
                    local value = parameter.value
                    if parameter.short == 'VehicleIndex' then value = ghostFlame.GAME_FLAME_INDEX end
                    ghostFlame.setValue(flame, parameter.short, parameter.kind, value)
                end
                flames[#flames + 1] = {component = flame}
            end
        end
    end
    if #flames == 0 then return 'sin llama del juego (no se pudo crear en ningún motor)' end
    ghost.gameFlames = flames
    return string.format('llama del juego en %d motor(es), con VehicleIndex %d', #flames, ghostFlame.GAME_FLAME_INDEX)
end

-- Cómo mueve el juego los interruptores de la llama (en el efecto, -1 = sí; igual en tu llama y en la de la IA):
--   postcombustión: AfterburnerPressed es un pulso de ~0,27 s al empezar, y AfterburnerRecovering está en "no"
--     mientras dura (y en "sí" el resto del tiempo)
--   ramjet: 0,55 s de arranque (RamjetEngaging y RamjetMode); luego RamjetActive, con un pulso de RamjetPressed,
--     hasta que acaba (RamjetMode sigue en "sí"); al terminar, 1 s de RamjetCoolingDown
function ghostFlame.switchesFor(boost, since, previous)
    local engage, pulse = ghostFlame.RAMJET_ENGAGE_SECONDS, ghostFlame.PULSE_SECONDS
    return {
        AfterburnerPressed = boost == 'A' and since < pulse,
        AfterburnerRecovering = boost ~= 'A',
        RamjetMode = boost == 'R',
        RamjetEngaging = boost == 'R' and (ghostFlame.HOLD_RAMJET_ENGAGING or since < engage),
        RamjetActive = boost == 'R' and since >= engage,
        RamjetPressed = boost == 'R' and since >= engage and since < engage + pulse,
        RamjetCoolingDown = boost ~= 'R' and previous == 'R' and since < ghostFlame.RAMJET_COOLDOWN_SECONDS,
    }
end

-- Cada fotograma: los interruptores de la llama del juego siguen al fantasma (solo se tocan los que cambian)
function ghostFlame.updateGameFlames(ghost, elapsed)
    local point = ghostPointAt(ghost.points, elapsed)
    local boost = point and point.boost
    if boost ~= 'A' and boost ~= 'R' then boost = 'N' end
    local state = ghost.gameFlameState
    if not state or state.boost ~= boost or elapsed < state.since then
        state = {boost = boost, since = elapsed, previous = state and state.boost}
        ghost.gameFlameState = state
    end
    local switches = ghostFlame.switchesFor(boost, elapsed - state.since, state.previous)
    for _, flame in ipairs(ghost.gameFlames) do
        if isValid(flame.component) then
            flame.switches = flame.switches or {}
            for name, on in pairs(switches) do
                if flame.switches[name] ~= on then
                    flame.switches[name] = on
                    pcall(function() flame.component:SetVariableBool(FName(name), on) end)
                end
            end
        end
    end
end

local function moveRaceGhost()
    local race = modState.race
    local ghost = race and race.ghost
    local anchor
    if ghost and ghost.clockKind == 'event' then
        -- before the GO is read, from your first move and how long before the GO the ghost moved
        anchor = race.eventZero or (race.startTime and race.startTime - math.min(0, ghost.points[1].t))
    elseif ghost then anchor = race.startTime end
    if not ghost or not anchor then return end
    if not isValid(ghost.actor) then removeRaceGhost(race); return end   -- borra también las piezas que queden (estela)
    local now = race.clock(); if not now then return end
    if ghost.needsHeights then return end
    local elapsed, points = now - anchor, ghost.points
    if elapsed > points[#points].t + 3 then removeRaceGhost(race); return end
    local index = ghost.index
    while index < #points - 1 and points[index + 1].t <= elapsed do index = index + 1 end
    while index > 1 and points[index].t > elapsed do index = index - 1 end
    ghost.index = index
    local from, to = points[index], points[index + 1] or points[index]
    local fraction = to.t > from.t and math.max(0, math.min(1, (elapsed - from.t) / (to.t - from.t))) or 0
    local location = {X = from.x + (to.x - from.x) * fraction, Y = from.y + (to.y - from.y) * fraction, Z = from.z + (to.z - from.z) * fraction + ghost.lift}
    if ghost.rotates then
        local function angle(a, b) local difference = ((b - a + 540) % 360) - 180; return a + difference * fraction end
        ghostTrail.moveActor(ghost.actor, location, {Pitch = angle(from.pitch, to.pitch), Yaw = angle(from.yaw, to.yaw), Roll = angle(from.roll, to.roll)})
    else
        -- sin giro grabado: mantiene el que tiene (se lee una vez)
        ghost.fixedRotation = ghost.fixedRotation or ghost.actor:K2_GetActorRotation()
        local facing = ghost.fixedRotation
        ghostTrail.moveActor(ghost.actor, location, {Pitch = facing.Pitch, Yaw = facing.Yaw, Roll = facing.Roll})
    end
    if ghost.trail then pcall(ghostTrail.draw, ghost, elapsed, race) end
    if ghost.flameEngines then pcall(ghostFlame.update, ghost, elapsed) end
    if ghost.gameFlames then pcall(ghostFlame.updateGameFlames, ghost, elapsed) end
end
local ghostLoopStarted, ghostMoveFailed = false, false
local function startGhostLoop()
    if ghostLoopStarted then return end
    ghostLoopStarted = true
    local function step()
        local ok, err = pcall(moveRaceGhost)
        if not ok then
            if not ghostMoveFailed then ghostMoveFailed = true; log('Fantasma: no se pudo mover: ' .. tostring(err)) end
            pcall(removeRaceGhost, modState.race)
        end
    end
    if type(LoopInGameThreadAfterFrames) == 'function' then
        LoopInGameThreadAfterFrames(1, step); log('Fantasma: se mueve en cada fotograma')
    else
        LoopInGameThreadWithDelay(1, step); log('Fantasma: se mueve con el bucle del juego (sin LoopInGameThreadAfterFrames)')
    end
end
-- Hologram of your vehicle: decorative copies of the 3D models of your vehicle in this race (no
-- physics, no collision, not a racer), attached to an empty base that follows the ghost, painted with
-- the engine's translucent widget material in one colour. If anything fails, the sphere is used.
-- Colour chosen in the app (⚙ menu > Ghost colour), saved as ghost_color in preferences.txt
local GHOST_COLORS = {cyan = {0.35, 0.85, 1}, white = {1, 1, 1}, red = {1, 0.2, 0.15}, green = {0.3, 1, 0.4}, gold = {1, 0.75, 0.2}, purple = {0.7, 0.35, 1}}
local function ghostColor()
    local name = 'cyan'
    local file = io.open(modFile('preferences.txt'), 'r')
    if file then
        for line in file:lines() do local key, value = line:match('^([%w_]+)\t([%w_]*)'); if key == 'ghost_color' and GHOST_COLORS[value] then name = value end end
        file:close()
    end
    local rgb = GHOST_COLORS[name]
    return {R = rgb[1], G = rgb[2], B = rgb[3], A = 0.45}, name
end

-- Opciones del fantasma elegidas en la app (menú de ajustes), guardadas en preferences.txt y leídas al
-- empezar cada carrera: ghost_enabled (on/off), ghost_transparency (low/medium/high), ghost_trail (on/off),
-- ghost_flame (on/off; aún sin botón en la app, encendida por defecto mientras se prueba),
-- ghost_trail_transparency (low/medium/high), ghost_flame_mode (game/own/both; game por defecto)
local ghostSettings = {enabled = true, transparency = 'medium', trail = false, flame = true, trailTransparency = 'low', flameMode = 'game'}
-- Holograma más ligero de dibujar (el cristal es caro y se notaban tirones al verlo desde abajo):
-- no se copian las piezas pequeñas de tu vehículo (radio menor que este, en cm), salvo las de los motores,
-- y cada pieza usa un nivel de detalle más bajo (1 = el más detallado, 2 = el siguiente...; si la malla no
-- tiene tantos, el juego usa el último que tenga)
ghostSettings.HOLOGRAM_MIN_RADIUS_CM = 15
ghostSettings.HOLOGRAM_FORCED_LOD = 2
-- Transparencia: glass = Max, Min, Edge y Highlight Opacity del cristal; widget = opacidad del material de reserva
-- (los primeros valores estaban demasiado juntos y no se notaba la diferencia: ahora van más separados)
-- Material: el cristal del juego (con color). El translúcido sencillo del motor tiene opacidad de verdad, pero
-- en el mundo 3D sale negro aunque se le ponga una textura blanca (probado el 2026-11-02): queda de reserva.
-- Con el cristal, bajar la opacidad no deja ver a través, solo lo oscurece; por eso los niveles son suaves.
-- glass: Max, Min, Edge y Highlight Opacity del cristal; body/boost: opacidad si se usa el material de reserva
-- thin: Thin Translucent Multiplier del cristal: cuanto más alto, más deja ver lo de detrás (probado: con 1 se
-- veía transparente y con 0,1 sólido)
-- flameThin: el de la llama, más sólida que el cuerpo (si no, se mezclaba con el color del fantasma y se apagaba)
ghostSettings.TRANSPARENCY_LEVELS = {
    -- Edge Opacity (tercer valor de glass) baja con la opacidad: casi fijo, el contorno de cada pieza se veía
    -- como una línea negra al bajarla, como si se viera la malla
    low = {glass = {0.75, 0.4, 0.8, 0.8}, thin = 0.1, flameThin = 0.05, body = 0.8, boost = 0.9},
    medium = {glass = {0.55, 0.25, 0.5, 0.6}, thin = 0.5, flameThin = 0.15, body = 0.45, boost = 0.7},
    high = {glass = {0.35, 0.15, 0.25, 0.4}, thin = 1, flameThin = 0.3, body = 0.12, boost = 0.5},
}
-- La estela tiene su propia transparencia en la app (ghost_trail_transparency), aparte de la del vehículo.
-- low (la opción por defecto) es casi sólida: con {0,75; 0,4; 0,75; 0,8} y thin 0,1 se veía poco.
-- opacity: la del material de reserva.
ghostSettings.TRAIL_LEVELS = {
    low = {glass = {0.95, 0.7, 0.9, 1}, thin = 0.03, opacity = 0.9},
    medium = {glass = {0.55, 0.25, 0.5, 0.6}, thin = 0.5, opacity = 0.6},
    high = {glass = {0.35, 0.15, 0.25, 0.4}, thin = 1, opacity = 0.35},
}
-- Cuánto se aclara el color del borde (Color Edge) mezclándolo con blanco: 0 = el mismo color, 1 = blanco
ghostSettings.EDGE_LIGHTEN = 0.5
function ghostSettings.read()
    local enabled, transparency, trail, flame, trailTransparency, flameMode = 'on', 'medium', 'off', 'on', 'low', 'game'   -- valores por defecto
    local file = io.open(modFile('preferences.txt'), 'r')
    if file then
        for line in file:lines() do
            local key, value = line:match('^([%w_]+)\t([%w_]*)')
            if key == 'ghost_enabled' then enabled = value
            elseif key == 'ghost_transparency' then transparency = value
            elseif key == 'ghost_trail' then trail = value
            elseif key == 'ghost_flame' then flame = value
            elseif key == 'ghost_trail_transparency' then trailTransparency = value
            elseif key == 'ghost_flame_mode' then flameMode = value
            end
        end
        file:close()
    end
    ghostSettings.enabled = enabled ~= 'off'
    ghostSettings.trail = trail == 'on'
    ghostSettings.flame = flame ~= 'off'
    ghostSettings.transparency = ghostSettings.TRANSPARENCY_LEVELS[transparency] and transparency or 'medium'
    ghostSettings.trailTransparency = ghostSettings.TRAIL_LEVELS[trailTransparency] and trailTransparency or 'low'
    ghostSettings.flameMode = (flameMode == 'own' or flameMode == 'both') and flameMode or 'game'   -- la del juego, por defecto
end

-- use: 'body' (el holograma, por defecto), 'flame' (la llama) o 'trail' (la estela, siempre igual)
-- options (opcional): glass = nombre del cristal que hay que usar; highlight = brillo (Highlight Color Multiplier)
hologramMaterial = function(world, colorOverride, use, options)
    options = options or {}
    local color, colorName = ghostColor()
    if colorOverride then color, colorName = colorOverride, use or 'efecto' end
    local level = ghostSettings.TRANSPARENCY_LEVELS[ghostSettings.transparency]
    local glassOpacity, thin, opacity = level.glass, level.thin, level.body
    if use == 'flame' then thin, opacity = level.flameThin, level.boost end
    if use == 'trail' then
        local trailLevel = ghostSettings.TRAIL_LEVELS[ghostSettings.trailTransparency]
        glassOpacity, thin, opacity = trailLevel.glass, trailLevel.thin, trailLevel.opacity
    end
    local materials = StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
    -- 1) A glass material of the game with colour settings (tinted glass looks like a hologram)
    for _, entry in ipairs(ghostLook.candidates) do
        local hasColor = false
        for _, name in ipairs(entry.vectors) do if name:find('Color', 1, true) then hasColor = true end end
        if hasColor and entry.name:find(options.glass or 'Glass', 1, true) then
            local dynamic
            pcall(function() dynamic = materials:CreateDynamicMaterialInstance(world, entry.material, FName('GhostHologram'), 0) end)
            if isValid(dynamic) then
                -- El borde (Color Edge), con el color aclarado: con el mismo color se veía como una línea oscura
                local lighten = ghostSettings.EDGE_LIGHTEN
                local function lighter(value) return value < 1 and value + (1 - value) * lighten or value end
                for _, name in ipairs(entry.vectors) do
                    local tint = {R = color.R, G = color.G, B = color.B, A = 1}
                    if name:find('Edge', 1, true) then tint = {R = lighter(color.R), G = lighter(color.G), B = lighter(color.B), A = 1} end
                    pcall(function() dynamic:SetVectorParameterValue(FName(name), tint) end)
                end
                local glass = glassOpacity
                -- La llama, sin borde: el contorno con la misma opacidad que el centro, para que el color se vea lleno
                local edgeOpacity = use == 'flame' and glass[1] or glass[3]
                local scalars = {{'Max Opacity', glass[1]}, {'Min Opacity', glass[2]}, {'Edge Opacity', edgeOpacity}, {'Highlight Opacity', glass[4]},
                    {'Thin Translucent Multiplier', thin}}
                -- La llama: más brillo sin cambiar el tono
                if options.highlight then scalars[#scalars + 1] = {'Highlight Color Multiplier', options.highlight} end
                for _, pair in ipairs(scalars) do
                    pcall(function() dynamic:SetScalarParameterValue(FName(pair[1]), pair[2]) end)
                end
                return dynamic, 'cristal ' .. (entry.name:match('([^%.:/ ]+)$') or '') .. ', color ' .. colorName .. ', transparencia ' .. ghostSettings.transparency
            end
        end
    end
    -- Si se pidió un cristal concreto y no está, no se usa la reserva (para comparar cristales)
    if options.glass then return nil, 'sin el cristal ' .. options.glass end
    -- 2) Reserve: the engine's translucent widget material, with real opacity (it rendered black in the world)
    local candidate
    for _, entry in ipairs(ghostLook.candidates) do if entry.name:find('Widget3DPassThrough_Translucent', 1, true) then candidate = entry; break end end
    if candidate then
        local rendering = StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
        local dynamic, plain
        pcall(function() dynamic = materials:CreateDynamicMaterialInstance(world, candidate.material, FName('GhostHologram'), 0) end)
        if isValid(dynamic) then
            -- El color se multiplica por la textura SlateUI: tiene que ser blanca. Primero la blanca del motor;
            -- si no está, una pintada en el momento (esa salía negra y dejaba el fantasma y las llamas sin color).
            local textureNote = 'textura blanca del motor'
            plain = StaticFindObject('/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture')
            if not isValid(plain) and type(LoadAsset) == 'function' then pcall(function() plain = LoadAsset('/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture') end) end
            if not isValid(plain) then
                textureNote = 'textura pintada'
                pcall(function() plain = rendering:CreateRenderTarget2D(world, 4, 4, 2, {R = 1, G = 1, B = 1, A = 1}, false) end)
                if not isValid(plain) then pcall(function() plain = rendering:CreateRenderTarget2D(world, 4, 4, 2, {R = 1, G = 1, B = 1, A = 1}, false, false) end) end
                if isValid(plain) then pcall(function() rendering:ClearRenderTarget2D(world, plain, {R = 1, G = 1, B = 1, A = 1}) end) end
            end
            if isValid(plain) then pcall(function() dynamic:SetTextureParameterValue(FName('SlateUI'), plain) end) else textureNote = 'sin textura' end
            pcall(function() dynamic:SetScalarParameterValue(FName('OpacityFromTexture'), 0) end)
            pcall(function() dynamic:SetVectorParameterValue(FName('TintColorAndOpacity'), {R = color.R, G = color.G, B = color.B, A = opacity}) end)
            return dynamic, string.format('translúcido, color %s, transparencia %s (opacidad %d %%, %s)', colorName, ghostSettings.transparency,
                math.floor(opacity * 100 + 0.5), textureNote)
        end
    end
    return nil, 'sin material translúcido'
end
-- UE4SS hands arrays back as TArray objects, not Lua tables
local function toList(array)
    local raw, list = {}, {}
    if type(array) == 'table' then raw = array
    else pcall(function() array:ForEach(function(_, element) raw[#raw + 1] = element end) end) end
    for _, entry in ipairs(raw) do
        local value = entry
        for _ = 1, 2 do
            if isValid(value) then break end
            local ok, inner = pcall(function() return value:get() end)
            if not ok then break end
            value = inner
        end
        if isValid(value) then list[#list + 1] = value end
    end
    return list
end
-- Actors attached to the pawn (an out parameter: UE4SS fills the table it is given)
local function attachedActors(pawn)
    local out, list = {}, {}
    local _, returned = pcall(function() return pawn:GetAttachedActors(out, true) end)
    for _, entry in ipairs(type(returned) == 'table' and returned or out) do
        local value = entry
        if not isValid(value) then pcall(function() value = entry:get() end) end
        if isValid(value) then list[#list + 1] = value end
    end
    return list
end
-- (va aquí, después de attachedActors y toList, para poder usarlas)
-- La llama de motor de tu vehículo que va pegada a una pieza (la que copió el holograma)
function ghostFlame.findSourceFlame(pawn, enginePart)
    local class = StaticFindObject('/Script/Niagara.NiagaraComponent')
    if not isValid(class) then return nil end
    local owners = {pawn}
    for _, attached in ipairs(attachedActors(pawn)) do owners[#owners + 1] = attached end
    local partAddress = address(enginePart)
    for _, owner in ipairs(owners) do
        local components = {}
        pcall(function() components = toList(owner:K2_GetComponentsByClass(class)) end)
        for _, component in ipairs(components) do
            local parentAddress, assetName = nil, ''
            pcall(function() parentAddress = address(component:GetAttachParent()) end)
            pcall(function() assetName = fullName(readProperty(component, 'Asset')) end)
            if parentAddress and parentAddress == partAddress and assetName:find(ghostFlame.ENGINE_EFFECT, 1, true) then return component end
        end
    end
    return nil
end

-- What the vehicle is made of, for the log: component classes of the pawn and of the actors attached to it
local function describeVehicle(pawn)
    local actors, lines, counts = {pawn}, {}, {}
    for _, attached in ipairs(attachedActors(pawn)) do actors[#actors + 1] = attached end
    local componentClass = StaticFindObject('/Script/Engine.ActorComponent')
    for _, actor in ipairs(actors) do
        local actorName = '?'; pcall(function() actorName = actor:GetFullName() end)
        lines[#lines + 1] = '== ' .. actorName
        local components = {}
        pcall(function() components = toList(actor:K2_GetComponentsByClass(componentClass)) end)
        for _, component in ipairs(components) do
            local fullName = '?'; pcall(function() fullName = component:GetFullName() end)
            local className = fullName:match('^(%S+)') or '?'
            counts[className] = (counts[className] or 0) + 1
            local visible, mesh = '?', ''
            pcall(function() visible = tostring(component:IsVisible()) end)
            pcall(function() local value = component.StaticMesh; if isValid(value) then mesh = ' malla ' .. value:GetFullName() end end)
            pcall(function() local value = component.SkeletalMeshAsset or component.SkeletalMesh; if isValid(value) then mesh = ' esqueleto ' .. value:GetFullName() end end)
            if className:find('Mesh') or className:find('Primitive') then lines[#lines + 1] = string.format('%s | visible %s%s', fullName, visible, mesh) end
        end
    end
    writeFile(MOD_FOLDER .. 'race_ghosts/vehicle.txt', table.concat(lines, '\n') .. '\n', 'w')
    local parts = {}
    for key, count in pairs(counts) do if key:find('Mesh') then parts[#parts + 1] = key .. ' ' .. count end end
    table.sort(parts)
    return string.format('%d actores, %s (detalle en race_ghosts\\vehicle.txt)', #actors, table.concat(parts, ', '))
end
local lastHologramParts = {}
local function spawnVehicleHologram(pawn, world)
    lastHologramParts = {}
    local material, materialNote = hologramMaterial(world)
    if not material then return nil, materialNote end
    local actorClass = StaticFindObject('/Script/Engine.StaticMeshActor')
    local skeletalClass = StaticFindObject('/Script/Engine.SkeletalMeshActor')
    local meshClasses = {{StaticFindObject('/Script/Engine.StaticMeshComponent'), 'static'}, {StaticFindObject('/Script/Engine.SkeletalMeshComponent'), 'skeletal'}}
    local pawnLocation, pawnRotation = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
    local base = world:SpawnActor(actorClass, {X = pawnLocation.X, Y = pawnLocation.Y, Z = pawnLocation.Z}, {Pitch = pawnRotation.Pitch, Yaw = pawnRotation.Yaw, Roll = pawnRotation.Roll})
    if not isValid(base) then return nil, 'no se pudo crear la base' end
    pcall(function() readProperty(base, 'StaticMeshComponent'):SetMobility(2) end)
    local actors, parts, skippedSmall = {base}, {static = 0, skeletal = 0}, 0
    local engineSocket = FName(ghostTrail.ENGINE_SOCKET)
    -- Si una pieza es pequeña (y no es un motor: la llama y la estela salen de sus toberas)
    local function isSmallPart(component, mesh, scale)
        local radius
        pcall(function() radius = mesh:GetBounds().SphereRadius * math.max(math.abs(scale.X), math.abs(scale.Y), math.abs(scale.Z)) end)
        if not radius or radius >= ghostSettings.HOLOGRAM_MIN_RADIUS_CM then return false end
        local isEngine = false
        pcall(function() isEngine = component:DoesSocketExist(engineSocket) end)
        return not isEngine
    end
    for _, pair in ipairs(meshClasses) do
        local componentClass, kind = pair[1], pair[2]
        local components = {}
        local owners = {pawn}
        pcall(function() for _, attached in ipairs(attachedActors(pawn)) do owners[#owners + 1] = attached end end)
        for _, owner in ipairs(owners) do
            if isValid(componentClass) then pcall(function() for _, component in ipairs(toList(owner:K2_GetComponentsByClass(componentClass))) do components[#components + 1] = component end end) end
        end
        for _, component in ipairs(components) do
            if #actors > 300 then break end
            local visibleOk, visible = pcall(function() return component:IsVisible() end)
            local mesh
            pcall(function() mesh = kind == 'static' and component.StaticMesh or (component.SkeletalMeshAsset or component.SkeletalMesh) end)
            local componentName, meshName = '', ''
            pcall(function() componentName = component:GetFullName() end)
            pcall(function() meshName = mesh:GetFullName() end)
            -- the proxy box around the vehicle (an engine cube) is not part of its look
            local isProxy = componentName:find('Proxy', 1, true) or meshName:find('/Engine/', 1, true)
            local location, rotation, scale
            if visibleOk and visible and isValid(mesh) and not isProxy then
                location, rotation, scale = component:K2_GetComponentLocation(), component:K2_GetComponentRotation(), component:K2_GetComponentScale()
                if kind == 'static' and isSmallPart(component, mesh, scale) then skippedSmall = skippedSmall + 1; location = nil end
            end
            if location then
                local copy = world:SpawnActor(kind == 'static' and actorClass or skeletalClass, {X = location.X, Y = location.Y, Z = location.Z},
                    {Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll})
                if isValid(copy) then
                    local copyComponent = readProperty(copy, kind == 'static' and 'StaticMeshComponent' or 'SkeletalMeshComponent')
                    pcall(function() copyComponent:SetMobility(2) end)
                    if kind == 'static' then
                        pcall(function() copyComponent:SetStaticMesh(mesh) end)
                        pcall(function() copyComponent:SetForcedLodModel(ghostSettings.HOLOGRAM_FORCED_LOD) end)
                    else
                        local setOk = pcall(function() copyComponent:SetSkeletalMeshAsset(mesh) end)
                        if not setOk then pcall(function() copyComponent:SetSkeletalMesh(mesh, true) end) end
                    end
                    pcall(function() copyComponent:SetCollisionEnabled(0) end)
                    ghostTrail.lightRendering(copyComponent)
                    pcall(function() copy:SetActorScale3D({X = scale.X, Y = scale.Y, Z = scale.Z}) end)
                    local slots = 1
                    pcall(function() slots = copyComponent:GetNumMaterials() end)
                    for slot = 0, math.max(0, slots - 1) do pcall(function() copyComponent:SetMaterial(slot, material) end) end
                    pcall(function() copy:K2_AttachToActor(base, FName('None'), 1, 1, 1, false) end)
                    actors[#actors + 1] = copy
                    lastHologramParts[#lastHologramParts + 1] = {copy = copy, source = component}
                    parts[kind] = parts[kind] + 1
                end
            end
        end
    end
    if #actors == 1 then pcall(function() base:K2_DestroyActor() end); local described = 'sin descripción'; pcall(function() described = describeVehicle(pawn) end); return nil, 'el vehículo no tiene modelos visibles; ' .. described end
    pcall(describeVehicle, pawn)   -- race_ghosts\\vehicle.txt, to see which pieces exist
    return base, actors, string.format('holograma de tu vehículo (%d piezas, %d con esqueleto, %d pequeñas sin copiar, detalle %d; material %s)', parts.static + parts.skeletal,
        parts.skeletal, skippedSmall, ghostSettings.HOLOGRAM_FORCED_LOD, tostring(materialNote))
end
-- Friends' files and ghosts saved before carry no rotation: it follows the direction of travel.
local function fillGhostRotations(points)
    if points[1] and points[1].yaw then return end
    for index, point in ipairs(points) do
        local before, after = points[math.max(1, index - 2)], points[math.min(#points, index + 2)]
        local dx, dy, dz = after.x - before.x, after.y - before.y, (after.z or 0) - (before.z or 0)
        local horizontal = math.sqrt(dx * dx + dy * dy)
        point.yaw = horizontal > 1 and math.deg(math.atan(dy, dx)) or (points[index - 1] and points[index - 1].yaw or 0)
        point.pitch = horizontal > 1 and math.deg(math.atan(dz, horizontal)) or 0
        point.roll = 0
    end
end

local function startRaceGhost(race, pawn)
    if not GHOST_ENABLED or not isArcadeRace(race) then return end
    pcall(ghostSettings.read)   -- las opciones pueden haber cambiado en la app desde la última carrera
    if not ghostSettings.enabled then log('Fantasma: desactivado en la app (se sigue guardando tu mejor carrera)'); return end
    local startedAt = os.clock()
    local own = readGhostFile(RACE_GHOSTS_FOLDER .. race.event.id .. '.txt') or readGhostFile(MOD_FOLDER .. 'race_ghost_' .. race.event.id .. '.txt')
    local friend = readGhostFile(RACE_GHOSTS_FOLDER .. race.event.id .. '.friend.txt')
    if friend and friend.clockKind ~= 'event' then friend = nil end   -- rebuilt from laps by older apps: out of step at the start
    local ghost = own
    if friend and (not own or friend.total < own.total) then ghost = friend end
    if not ghost then log('Fantasma: aún no hay carrera guardada en este evento (se guarda la primera que termines)'); return end
    local needsHeights = false
    for _, point in ipairs(ghost.points) do if not point.z then needsHeights = true; break end end
    if needsHeights then
        local start = toVector(pawn:K2_GetActorLocation())
        for _, point in ipairs(ghost.points) do point.z = nil; point.placeholderZ = start.Z end
    end
    -- The recorded height follows the hover bobbing of the vehicle (tens of cm every 0.1 s), which made
    -- the sphere shake: it is smoothed with a moving average of ±0.4 s.
    -- Con giro grabado (holograma) basta con ±0,1 s: con ±0,4 s se hundía en las crestas y se quedaba corto en los saltos
    local points, heights = ghost.points, {}
    local smoothing = points[1].yaw and 1 or 4   -- puntos a cada lado (cada punto son 0,1 s)
    if not needsHeights then
        for index = 1, #points do
            local sum, count = 0, 0
            for other = math.max(1, index - smoothing), math.min(#points, index + smoothing) do sum = sum + points[other].z; count = count + 1 end
            heights[index] = sum / count
        end
        for index = 1, #points do points[index].z = heights[index] end
    end
    local first = {x = ghost.points[1].x, y = ghost.points[1].y, z = ghost.points[1].z or ghost.points[1].placeholderZ}
    -- While the circuit loads the vehicle is not assembled yet: the hologram is retried every half second
    -- until it has its pieces (during the intro); the sphere only if it still fails at the start.
    race.pendingGhost = {data = ghost, needsHeights = needsHeights, first = first, nextTry = 0,
        label = string.format('%s, %s', ghost == own and 'tu mejor carrera' or ghost.pilot, formatTime(ghost.total))}
    log('Fantasma: preparado (' .. race.pendingGhost.label .. string.format(', %.0f ms); se crea cuando tu vehículo esté montado', (os.clock() - startedAt) * 1000))
end
-- Whether the vehicle already has its visible pieces (cheap: nothing is created)
local function vehicleIsAssembled(pawn)
    local meshClass = StaticFindObject('/Script/Engine.StaticMeshComponent')
    if not isValid(meshClass) then return true end
    local owners = {pawn}
    for _, attached in ipairs(attachedActors(pawn)) do owners[#owners + 1] = attached end
    for _, owner in ipairs(owners) do
        local components = {}
        pcall(function() components = toList(owner:K2_GetComponentsByClass(meshClass)) end)
        for _, component in ipairs(components) do
            local ok, ready = pcall(function()
                local mesh = component.StaticMesh
                return component:IsVisible() and isValid(mesh) and not mesh:GetFullName():find('/Engine/', 1, true)
            end)
            if ok and ready then return true end
        end
    end
    return false
end
local function placePendingGhost(race, pawn)
    local pending = race.pendingGhost
    if not pending or os.clock() < pending.nextTry then return end
    pending.nextTry = os.clock() + 0.5
    local ghost, needsHeights, first = pending.data, pending.needsHeights, pending.first
    local worldOk, world = pcall(function() return pawn:GetWorld() end)
    if not worldOk then world = nil end
    local problem
    if not race.startTime and not vehicleIsAssembled(pawn) then return end   -- try again in half a second
    if not safeMode.blocked.ghost_vehicle and isValid(world) then
        local copyOk, base, actors, note = runGuarded('ghost_vehicle', spawnVehicleHologram, pawn, world)
        if copyOk and base then
            fillGhostRotations(ghost.points)
            race.ghost = {actor = base, actors = actors, parts = lastHologramParts, points = ghost.points, index = 1, lift = 0, rotates = true, clockKind = ghost.clockKind, needsHeights = needsHeights}
            log('Fantasma: aspecto: ' .. note)
        elseif not race.startTime then
            return   -- try again in half a second
        else
            log('Fantasma: no se pudo copiar tu vehículo (' .. tostring(copyOk and actors or base) .. '); se usa la esfera')
        end
    end
    race.pendingGhost = nil
    if not race.ghost then
        local actor
        actor, problem = spawnSphere(pawn, {X = first.x, Y = first.y, Z = first.z + GHOST_LIFT})
        if not actor then log('Fantasma: ' .. tostring(problem)); return end
        race.ghost = {actor = actor, points = ghost.points, index = 1, lift = GHOST_LIFT, clockKind = ghost.clockKind, needsHeights = needsHeights}
        if not safeMode.blocked.ghost_look then
            local _, look = runGuarded('ghost_look', dressGhostSphere, actor, world)
            log('Fantasma: aspecto: ' .. tostring(look))
        end
    end
    -- La estela tiene su propio nombre en el modo seguro: si el juego se cierra al crearla, se sabe que fue ella
    if TRAIL_ENABLED and ghostSettings.trail and race.ghost and isValid(world) and not safeMode.blocked.ghost_trail then
        local _, trailNote = runGuarded('ghost_trail', ghostTrail.spawn, race.ghost, pawn, world, vehicleStateData.vehicleType(race))
        log('Fantasma: ' .. tostring(trailNote))
    elseif not ghostSettings.trail then
        log('Fantasma: estela apagada en la app')
    end
    -- La llama del juego en los motores del holograma (prueba), con su propio nombre en el modo seguro
    -- ghost_flame_mode: own (piezas propias), game (llama del juego) o both (las dos)
    local flameMode = ghostSettings.flameMode
    if ghostSettings.flame and race.ghost and race.ghost.parts and flameMode ~= 'game' and not safeMode.blocked.ghost_flame then
        local _, flameNote = runGuarded('ghost_flame', ghostFlame.spawn, race.ghost, pawn)
        log('Fantasma: ' .. tostring(flameNote))
    end
    if ghostSettings.flame and race.ghost and race.ghost.parts and flameMode ~= 'own' and not safeMode.blocked.ghost_game_flame then
        local _, gameFlameNote = runGuarded('ghost_game_flame', ghostFlame.spawnGameFlames, race.ghost, pawn)
        log('Fantasma: ' .. tostring(gameFlameNote))
    end
    log('Fantasma: ' .. pending.label .. (problem and (' (' .. problem .. ')') or ''))
    startGhostLoop()
end

local function recordSample(race, playerController)
    local pawn = playerController.Pawn
    local now = race.clock()
    if not now then return end
    local position = toVector(pawn:K2_GetActorLocation())
    local velocity
    local ok, pawnVelocity = pcall(function() return pawn:GetVelocity() end)
    if ok and pawnVelocity then velocity = toVector(pawnVelocity)
    elseif race.lastPosition and now > race.lastSampleTime then
        local elapsed = now - race.lastSampleTime
        velocity = {X = (position.X - race.lastPosition.X) / elapsed, Y = (position.Y - race.lastPosition.Y) / elapsed,
            Z = (position.Z - race.lastPosition.Z) / elapsed}
    else velocity = {X = 0, Y = 0, Z = 0} end
    race.lastPosition, race.lastSampleTime = position, now
    -- Hacia dónde vas (en horizontal), para la estela del fantasma; parado se mantiene la última
    local flatSpeed = math.sqrt(velocity.X * velocity.X + velocity.Y * velocity.Y)
    if flatSpeed > 500 then race.playerForward = {X = velocity.X / flatSpeed, Y = velocity.Y / flatSpeed} end
    local kmh = math.sqrt(velocity.X * velocity.X + velocity.Y * velocity.Y + velocity.Z * velocity.Z) * 0.036
    local forward = pawn:GetActorForwardVector()
    local heading = math.deg(math.atan(forward.Y, forward.X))
    local routeDistance, segment, offsetFromRoute, routeHeight = projectOntoRoute(race, position, race.routeHintSegment)
    race.routeHintSegment = segment
    local routeLength = race.routeLength
    local events = ''
    local distance

    if not race.startTime then
        distance = routeDistance
        if kmh > START_SPEED_KMH then
            race.startTime = now
            local segmentStart, segmentEnd = race.routePoints[segment], race.routePoints[segment + 1]
            local dot = forward.X * (segmentEnd.X - segmentStart.X) + forward.Y * (segmentEnd.Y - segmentStart.Y) + forward.Z * (segmentEnd.Z - segmentStart.Z)
            race.direction = dot < 0 and -1 or 1
            race.gates = {}
            for _, gate in ipairs(race.routeGates) do
                race.gates[#race.gates + 1] = {distance = race.direction == -1 and (routeLength - gate.routeDistance) or gate.routeDistance, position = gate.position,
                    normal = {X = gate.tangent.X * race.direction, Y = gate.tangent.Y * race.direction, Z = gate.tangent.Z * race.direction}}
            end
            table.sort(race.gates, function(first, second) return first.distance < second.distance end)
            race.checkpointDistances = {}
            for index, gate in ipairs(race.gates) do race.checkpointDistances[index] = gate.distance end
            local lapCount = tonumber(readProperty(race.gameState, 'LapCount'))
            if not lapCount or lapCount < 1 then lapCount = tonumber(readProperty(readProperty(race.gameState, 'RaceEventViewModel'), 'NumLaps')) end
            race.lapCount = (lapCount and lapCount >= 1) and lapCount or learnedTracks['laps|' .. trackKey(race)]
            distance = race.direction == -1 and (routeLength - routeDistance) or routeDistance
            race.lapStartTime = now
            race.runStartDistance = distance   -- donde arrancas (para el DIF desde el GO en los arranques lanzados)
            race.startDistance = learnedTracks['start|' .. trackKey(race)]
            race.rollingStart = race.lapCount == 1 and learnedTracks['rolling|' .. trackKey(race)] ~= nil or nil
            -- Bonificación de tiempo (Precisión): el juego dice si el evento la usa
            local startViewModel = readProperty(race.gameState, 'RaceEventViewModel')
            race.usesBonus = isValid(startViewModel) and readProperty(startViewModel, 'bWantsBonusTimer') == true or nil
            race.bonusTime, race.bonusChanges = 0, {}
            if race.usesBonus then log('Evento con bonificación de tiempo: vueltas y sectores con ella descontada') end
            local savedFinish = learnedTracks['finish|' .. trackKey(race)]
            if savedFinish then
                for index, checkpointDistance in ipairs(race.checkpointDistances) do
                    if math.abs(checkpointDistance - savedFinish) < 1000 then setFinishLine(race, index); log('Meta recordada: checkpoint ' .. index); break end
                end
            end
            events = events .. 'START '
            log(string.format('Salida. Sentido %s.', race.direction == 1 and 'de la ruta' or 'inverso'))
            pcall(readPanelLanguage)   -- the language may have changed in the app since the last race
            pcall(readRivals)
            -- The hologram was copied during the intro, when the vehicle may be posed differently (a bike on a
            -- slope ended up upright the whole race): its pieces are put again as your vehicle is at the GO
            if race.ghost and race.ghost.parts then
                local snapOk, snapError = pcall(function()
                    local base = race.ghost.actor
                    local where, facing = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
                    ghostTrail.moveActor(base, {X = where.X, Y = where.Y, Z = where.Z}, {Pitch = facing.Pitch, Yaw = facing.Yaw, Roll = facing.Roll})
                    for _, part in ipairs(race.ghost.parts) do
                        if isValid(part.copy) and isValid(part.source) then
                            local location, rotation = part.source:K2_GetComponentLocation(), part.source:K2_GetComponentRotation()
                            ghostTrail.moveActor(part.copy, {X = location.X, Y = location.Y, Z = location.Z},
                                {Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll})
                        end
                    end
                end)
                if not snapOk then log('Fantasma: no se pudo recolocar el holograma: ' .. tostring(snapError)) end
            end
            -- the ghost was made while the circuit loaded; friends' traces get their height now that the route is sampled
            if race.ghost and race.ghost.needsHeights then
                race.ghost.needsHeights = false
                pcall(fillGhostHeights, race, race.ghost.points, pawn)
            end
            pcall(function()
                local times, file = {}, io.open(EVENT_RECORDS_PATH, 'r')
                if file then
                    for line in file:lines() do local id, time = line:match('^([^\t]+)\t([%d%.]+)'); if id and tonumber(time) and tonumber(time) > 0 then times[id] = tonumber(time) end end
                    file:close()
                end
                modState.eventRecordTimes = times
            end)
        end
    else
        distance = race.direction == -1 and (routeLength - routeDistance) or routeDistance
        local previousDistance, previousTime = race.previousDistance, race.previousSampleTime
        local wrapped = previousDistance > 0.9 * routeLength and distance < 0.1 * routeLength
        local step = wrapped and (distance + routeLength - previousDistance) or (distance - previousDistance)
        -- Sudden jump back (crash, respawn): more than 30 m backwards
        if not wrapped and step < -3000 and step > -0.5 * routeLength then
            race.resetTimes[#race.resetTimes + 1] = now
            if #race.resetTimes > 64 then table.remove(race.resetTimes, 1) end
            events = events .. 'RESET '
        end
        -- Checkpoint crossings, combining two methods:
        --  1. Progress along the route: its time matches the game's official one.
        --  2. Passing through the gate: recovers the crossings the first one misses when you drive far
        --     from the centre. It waits 1.5 s in case the crossing from the first method arrives.
        local function registerCrossing(checkpoint, crossingTime)
            if race.lastCrossingTimes[checkpoint] and crossingTime - race.lastCrossingTimes[checkpoint] <= 2 then return end
            race.lastCrossingTimes[checkpoint] = crossingTime
            race.crossings[#race.crossings + 1] = {time = crossingTime, checkpoint = checkpoint}
            if #race.crossings > 256 then table.remove(race.crossings, 1) end
            onLiveCheckpointCrossing(race, checkpoint, crossingTime)
            events = events .. 'C' .. checkpoint .. ' '
        end
        race.pendingGateCrossings = race.pendingGateCrossings or {}
        if step > 0 and step < 0.05 * routeLength and now > previousTime then
            for index, checkpointDistance in ipairs(race.checkpointDistances) do
                local fraction
                if wrapped then
                    if checkpointDistance > previousDistance then fraction = (checkpointDistance - previousDistance) / step
                    elseif checkpointDistance <= distance then fraction = (checkpointDistance + routeLength - previousDistance) / step end
                elseif previousDistance < checkpointDistance and checkpointDistance <= distance then
                    fraction = (checkpointDistance - previousDistance) / step
                end
                if fraction then
                    race.pendingGateCrossings[index] = nil
                    registerCrossing(index, previousTime + fraction * (now - previousTime))
                end
            end
        end
        local previousPosition = race.previousPosition
        local jumpSquared = previousPosition and ((position.X - previousPosition.X) ^ 2 + (position.Y - previousPosition.Y) ^ 2 + (position.Z - previousPosition.Z) ^ 2) or math.huge
        if previousPosition and now > previousTime and jumpSquared < 20000 * 20000 then
            for index, gate in ipairs(race.gates) do
                local sideBefore = (previousPosition.X - gate.position.X) * gate.normal.X + (previousPosition.Y - gate.position.Y) * gate.normal.Y
                    + (previousPosition.Z - gate.position.Z) * gate.normal.Z
                local sideNow = (position.X - gate.position.X) * gate.normal.X + (position.Y - gate.position.Y) * gate.normal.Y + (position.Z - gate.position.Z) * gate.normal.Z
                if sideBefore < 0 and sideNow >= 0 then
                    local fraction = sideBefore / (sideBefore - sideNow)
                    local crossX = previousPosition.X + fraction * (position.X - previousPosition.X)
                    local crossY = previousPosition.Y + fraction * (position.Y - previousPosition.Y)
                    local crossZ = previousPosition.Z + fraction * (position.Z - previousPosition.Z)
                    local lateralSquared = (crossX - gate.position.X) ^ 2 + (crossY - gate.position.Y) ^ 2 + (crossZ - gate.position.Z) ^ 2
                    local alongRoute = math.abs(distance - gate.distance); alongRoute = math.min(alongRoute, routeLength - alongRoute)
                    local crossingTime = previousTime + fraction * (now - previousTime)
                    local recentlyCrossed = race.lastCrossingTimes[index] and math.abs(crossingTime - race.lastCrossingTimes[index]) < 1.5
                    if lateralSquared < GATE_RADIUS * GATE_RADIUS and alongRoute < 0.25 * routeLength and not recentlyCrossed then
                        race.pendingGateCrossings[index] = {time = crossingTime, seenAt = now}
                    end
                end
            end
        end
        for index, pending in pairs(race.pendingGateCrossings) do
            if now - pending.seenAt >= 1.5 then
                race.pendingGateCrossings[index] = nil
                registerCrossing(index, pending.time)
            end
        end
        if step > 0 and step < 0.05 * routeLength and now > previousTime then
            -- Without the official time: the start of the route is used as the finish line (closed circuits only)
            if wrapped and race.isClosedCircuit and not isValid(race.raceComponent) then
                local crossingTime = previousTime + (routeLength - previousDistance) / step * (now - previousTime)
                if race.lastRouteStartCrossing then
                    closeLap(race, crossingTime, crossingTime - race.lastRouteStartCrossing, false); events = events .. 'LAP '
                end
                race.lastRouteStartCrossing = crossingTime
                race.lapStartTime = crossingTime
            end
        end
    end

    -- Total time of the event and target time (the first one the game shows)
    local viewModel = readProperty(race.gameState, 'RaceEventViewModel')
    if isValid(viewModel) then
        local eventTime = readProperty(viewModel, 'CurrentEventTime')
        if type(eventTime) == 'number' and eventTime >= 0 then race.eventTime = eventTime end
        if race.usesBonus then
            local bonus = tonumber(readProperty(viewModel, 'CurrentBonusTime'))
            if bonus and math.abs(bonus - race.bonusTime) > 1e-4 then
                events = events .. string.format('BONUS%+.3f ', bonus - race.bonusTime)   -- marca en el CSV, para la app
                race.bonusTime = bonus
                race.bonusChanges[#race.bonusChanges + 1] = {time = now, total = bonus}
            end
        end
        if not race.target then
            local targetTime = readProperty(viewModel, 'CurrentTargetTime')
            if type(targetTime) == 'number' and targetTime > 0 then
                local playerName = readSafeText and readSafeText(viewModel, 'CurrentTargetPlayerName') or ''
                race.target = {time = targetTime, playerName = playerName ~= '' and playerName or nil, rank = tonumber(readProperty(viewModel, 'CurrentTargetTimeRank'))}
                log(string.format('Objetivo del evento: %s (%s, puesto %s)', formatTime(targetTime), tostring(race.target.playerName), tostring(race.target.rank)))
            end
        end
    end

    -- The game's official sectors: SectorStartServerTime changes when each sector starts and
    -- LapStartServerTime when each lap starts (the game's server clock).
    if isValid(race.raceComponent) then
        local sectorStart, lapStart = readProperty(race.raceComponent, 'SectorStartServerTime'), readProperty(race.raceComponent, 'LapStartServerTime')
        if type(sectorStart) == 'number' and type(lapStart) == 'number' then
            local official = race.officialSectors
            if not official then official = {current = {}, completed = {}}; race.officialSectors = official end
            if official.previousSectorStart and official.previousSectorStart > 0 and sectorStart > official.previousSectorStart + 1e-4 then
                local sectorTime = sectorStart - official.previousSectorStart
                official.current[#official.current + 1] = sectorTime
                events = events .. 'OS' .. #official.current .. ' '
                if lapStart > (official.lapStart or 0) + 1e-4 then
                    -- a lap starts: the previous one is closed with its official sectors
                    local sum = 0
                    for _, value in ipairs(official.current) do sum = sum + value end
                    official.completed[#official.completed + 1] = {sectorTimes = official.current, time = sum}
                    if #official.completed > 16 then table.remove(official.completed, 1) end
                    official.current = {}
                    if race.usesOfficialSectors == nil and race.checkpointDistances and race.finishCheckpoint then
                        race.usesOfficialSectors = #official.completed[#official.completed].sectorTimes == #race.checkpointDistances
                        writeSummaryLine(race, race.usesOfficialSectors and string.format('Sectores: oficiales del juego (%d)', #race.checkpointDistances)
                            or string.format('Sectores: el juego usa %d y hay %d checkpoints; se usan los detectados',
                                #official.completed[#official.completed].sectorTimes, #race.checkpointDistances))
                    end
                elseif race.usesOfficialSectors and race.liveLap.running and #race.liveLap.sectorTimes < #race.checkpointDistances - 1 then
                    race.liveLap.sectorTimes[#race.liveLap.sectorTimes + 1] = sectorTime
                end
            end
            if sectorStart > 0 then official.previousSectorStart = sectorStart end
            if lapStart > 0 then official.lapStart = lapStart end
        end
    end

    -- The game's official lap time
    if not isValid(race.raceComponent) then race.raceComponent = findRaceComponent(playerController) end
    local officialLapTime = readProperty(race.raceComponent, 'PreviousLapTime')
    if type(officialLapTime) == 'number' then
        if race.lastOfficialLapTime == nil then
            race.lastOfficialLapTime = officialLapTime
        elseif officialLapTime ~= race.lastOfficialLapTime then
            race.lastOfficialLapTime = officialLapTime
            if race.startTime and officialLapTime >= MIN_LAP_SECONDS and officialLapTime <= MAX_LAP_SECONDS then
                race.pendingOfficialLap = {lapTime = officialLapTime, time = now}
                events = events .. 'OFFICIAL '
            end
        end
    end
    if race.pendingOfficialLap and now >= race.pendingOfficialLap.time + OFFICIAL_TIME_WAIT_SECONDS then
        local pending = race.pendingOfficialLap
        race.pendingOfficialLap = nil
        handleOfficialLapTime(race, pending)
        events = events .. 'LAP '
    end
    -- End of the event according to the game itself
    if not race.eventEnded and not race.pendingOfficialLap and race.lapNumber > 0 and readProperty(race.raceComponent, 'bHasFinishedEvent') == true then
        finishEvent(race, 'el juego da el evento por terminado')
        events = events .. 'END '
    end

    local lapTime = race.lapStartTime and (now - race.lapStartTime) or 0
    -- Top and minimum speed of the lap in progress (the minimum from 4 s in, so the standing start does not count)
    if race.liveLap and race.liveLap.running and race.liveLap.startTime then
        local liveLap = race.liveLap
        liveLap.top = math.max(liveLap.top or 0, kmh)
        if now - liveLap.startTime > 4 then liveLap.minimum = math.min(liveLap.minimum or kmh, kmh) end
    end
    if race.ghost and race.startTime and isValid(race.ghost.actor) and now >= (race.ghostReportAt or 0) then
        race.ghostReportAt = now + 30
        pcall(function()
            local where = race.ghost.actor:K2_GetActorLocation()
            log(string.format('Fantasma: a %.0f s, a %.0f m de ti', now - race.startTime,
                math.sqrt((where.X - position.X) ^ 2 + (where.Y - position.Y) ^ 2 + (where.Z - position.Z) ^ 2) / 100))
        end)
    end
    -- Points of this race for its ghost, every 0.1 s from the start
    if race.eventTime and race.eventTime > 0.05 and not race.eventEnded then
        local zero = now - race.eventTime   -- the moment of the GO in the game clock (the lowest is the freshest reading)
        if not race.eventZero then events = events .. 'GO ' end   -- marca en el CSV: la app empieza ahí los arranques lanzados
        if not race.eventZero or zero < race.eventZero then race.eventZero = zero end
    end
    -- Arranque lanzado: la vuelta del panel corre desde el GO (el S1 acaba en la puerta)
    if race.rollingStart and race.eventZero and race.lapNumber == 0 and not race.eventEnded then
        local liveLap = race.liveLap
        if not liveLap or not liveLap.running then
            race.liveLap = {running = true, startTime = race.eventZero, sectorStartTime = race.eventZero, sectorTimes = {}}
        elseif #liveLap.sectorTimes == 0 then
            liveLap.startTime, liveLap.sectorStartTime = race.eventZero, race.eventZero
        end
    end
    -- Estado del vehículo (estela blanca y freno), una sola lectura para el fantasma y el CSV
    local stateOk, stateValues = pcall(vehicleStateData.read, race, pawn)
    if not stateOk then stateValues = {} end
    if (race.eventZero or race.startTime) and not race.eventEnded then
        local samples, elapsed = race.ghostSamples or {}, now - (race.eventZero or race.startTime)
        race.ghostSamples = samples
        -- by the clock, not by elapsed: elapsed jumps back when the GO is read (rolling starts), which left a gap
        if #samples == 0 or now >= samples[#samples].at + 0.1 then
            local rotationOk, rotation = pcall(function() return pawn:K2_GetActorRotation() end)
            local sampleBoostOk, sampleBoost = pcall(boostCode, race, pawn)
            local trailOk, trailCode = pcall(vehicleStateData.trailCode, vehicleStateData.vehicleType(race), stateValues)
            samples[#samples + 1] = {t = elapsed, at = now, x = position.X, y = position.Y, z = position.Z, boost = sampleBoostOk and sampleBoost or nil,
                yaw = rotationOk and rotation.Yaw or nil, pitch = rotationOk and rotation.Pitch or nil, roll = rotationOk and rotation.Roll or nil,
                trail = trailOk and trailCode or ''}
        end
    end
    local boostOk, boost = pcall(boostCode, race, pawn)
    local stateCsvOk, stateCsv = pcall(vehicleStateData.csv, stateValues)
    if not stateCsvOk then stateCsv = vehicleStateData.csv({}) end   -- columnas vacías
    race.telemetryBuffer[#race.telemetryBuffer + 1] = string.format('%.4f,%d,%.4f,%.1f,%.5f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f,%.2f,%.1f,%.1f,%s,%s,%s',
        now - race.clockStart, race.lapNumber + 1, lapTime, distance, distance / routeLength, position.X, position.Y, position.Z,
        velocity.X, velocity.Y, velocity.Z, kmh, heading, offsetFromRoute, position.Z - routeHeight, events, boostOk and boost or '', stateCsv)
    if race.filesDeferred and race.startTime and (now - race.startTime >= FILES_AFTER_SECONDS or race.lapNumber > 0 or race.eventEnded) then commitRaceFiles(race) end
    if #race.telemetryBuffer >= 50 then flushTelemetryBuffer(race) end
    race.previousDistance, race.previousSampleTime, race.previousPosition = distance, now, position
    -- Distance covered in the lap in progress, for the ghost and the live difference
    race.liveDifference = nil
    -- Finish not known yet (first race on a circuit): the distance along the route is kept for later
    if not race.finishCheckpoint and race.isClosedCircuit and race.startTime then
        local routeTrace = race.routeTrace or {}
        race.routeTrace = routeTrace
        if #routeTrace < 40000 then routeTrace[#routeTrace + 1] = {time = now, distance = distance} end
    end
    if race.finishCheckpoint and race.checkpointDistances and race.liveLap and race.liveLap.running and race.liveLap.startTime then
        local lapDistance
        if race.isClosedCircuit then lapDistance = (distance - race.checkpointDistances[race.finishCheckpoint] + routeLength) % routeLength
        elseif race.rollingStart and race.runStartDistance then lapDistance = distance - race.runStartDistance
        elseif race.startDistance then lapDistance = distance - race.startDistance end
        if lapDistance then
            local trace = race.distanceTrace or {}
            race.distanceTrace = trace
            local lastPoint = trace[#trace]
            -- At the start you set off from the grid, before the line: that stretch is negative
            -- (it does not count) instead of looking like the end of a lap.
            if race.isClosedCircuit and not lastPoint and lapDistance > 0.5 * routeLength then lapDistance = lapDistance - routeLength end
            if lastPoint and lapDistance < lastPoint.distance - 0.5 * routeLength then race.traceCrossedFinish = true end   -- crossed the line: wait for the lap to close
            if not race.traceCrossedFinish and lapDistance >= 0 then
                if not lastPoint or lapDistance > lastPoint.distance then trace[#trace + 1] = {time = now, distance = lapDistance} end
                if #trace > 20000 then table.remove(trace, 1) end
                local ghost = ghosts[race.ghostKey or race.panelBestKey or '']
                if ghost and lapDistance > 2000 then
                    local ghostTime = ghostTimeAtDistance(ghost, lapDistance)
                    if ghostTime then race.liveDifference = (now - race.liveLap.startTime - bonusData.between(race, race.liveLap.startTime, now)) - ghostTime end
                end
            end
        end
    end
    -- Speed over the last few seconds, to recognise the autopilot after the finish
    race.recentSpeeds = race.recentSpeeds or {}
    race.recentSpeeds[#race.recentSpeeds + 1] = {time = now, kmh = kmh}
    while #race.recentSpeeds > 0 and race.recentSpeeds[1].time < now - 4 do table.remove(race.recentSpeeds, 1) end
    checkEventEnd(race, now)
end

---------------------------------------------------------------------------
-- Timing panel: lap in progress, sectors, last, best and ideal lap.
-- When a lap closes it is shown complete for 5 seconds and then the panel moves to the next one.
---------------------------------------------------------------------------
local function formatRunningTime(seconds) local minutes = math.floor(seconds / 60); return string.format('%d:%04.1f', minutes, seconds - minutes * 60) end

local function updateTimingPanel(playerController, race)
    local settings = timingPanelSettings
    if not timingPanelLibrary or not (settings and settings.enabled) or not modState.timingPanelVisible or not race or not race.finishCheckpoint or not race.checkpointDistances then
        if modState.timingPanel then modState.timingPanel.show(false) end
        return
    end
    if os.clock() < modState.timingPanelRetryAt or safeMode.blocked.timing_panel then return end
    local sectorCount = #race.checkpointDistances - (race.startCheckpoint and 1 or 0)
    -- Arranque lanzado: S1 (GO a la puerta) más los sectores de la puerta a la meta
    if race.rollingStart and race.startCheckpoint and race.sectorCheckpointOrder then sectorCount = #race.sectorCheckpointOrder + 1 end
    local bottomRows = timingPanelLibrary.bottomRows(settings, race.lapCount)
    local panel = modState.timingPanel
    if not panel or panel.sectorCount ~= sectorCount or panel.bottomRowCount ~= #bottomRows or not panel.isAlive() then
        if panel then pcall(panel.close) end
        local created, result = runGuarded('timing_panel', timingPanelLibrary.createPanel, playerController, sectorCount, settings, bottomRows)
        if not created then error(result, 0) end
        modState.timingPanel = result
        modState.timingPanelPlaced = false
    end
    panel = modState.timingPanel
    local colors = timingPanelLibrary.COLORS
    panel.show(true)
    if not modState.timingPanelPlaced or modState.ticks % 50 == 0 then
        local layout = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        local viewportSize, viewportScale = layout:GetViewportSize(playerController), layout:GetViewportScale(playerController)
        if viewportScale and viewportScale > 0 then
            panel.place(viewportSize.X / viewportScale, viewportSize.Y / viewportScale); modState.timingPanelPlaced = true
        end
    end
    local now = race.lastSampleTime or 0
    local best = bestTimes[race.panelBestKey or bestTimesKey(race, sectorCount)] or {sectors = {}}
    local liveIsStartLap = isStartLap(race, race.lapNumber + 1)
    local liveBest = best
    if liveIsStartLap then
        local startBest = bestTimes[bestTimesKey(race, sectorCount, true)] or {sectors = {}}
        liveBest = {lap = startBest.lap, sectors = {}}
        for index = 1, sectorCount do liveBest.sectors[index] = (index == 1) and startBest.sectors[1] or best.sectors[index] end
    end
    local singleLap = race.lapCount == 1
    local compareWithPrevious = settings.compareWith == 'previous'
    local heldLap = race.heldLap and now < race.heldLap.showUntil and race.heldLap or nil
    race.ghostKey = liveIsStartLap and bestTimesKey(race, sectorCount, true) or (race.panelBestKey or bestTimesKey(race, sectorCount))
    -- Live difference against your best lap (the ghost); when a lap closes, the final one
    local differenceRow = panel.rowOf('live_difference')
    if differenceRow then
        panel.setCell(differenceRow, 1, panelTexts.difference, colors.label)
        local difference
        if heldLap then
            local reference = heldLap.ghostLapTime or heldLap.best
            difference = reference and (heldLap.time - reference) or nil
        else difference = race.liveDifference end
        if difference then
            panel.setCell(differenceRow, 2, formatSignedDifference(difference), math.abs(difference) < 0.0005 and colors.dim or (difference < 0 and colors.gain or colors.loss))
        else panel.setCell(differenceRow, 2, '--', colors.dim) end
        panel.setCell(differenceRow, 3, '', colors.dim)
    end
    -- Sector bars: colour of each sector of the lap (faint grey if you have not driven it yet)
    if panel.hasSectorBars then
        for index = 1, sectorCount do
            if heldLap then panel.setSectorBar(index, heldLap.sectorsValid and heldLap.sectorColors[index] or nil)
            else
                local sectorTime = race.liveLap.running and race.liveLap.sectorTimes[index]
                local previousTime = (not liveIsStartLap) and race.previousSectorTimes and race.previousSectorTimes[index] or nil
                panel.setSectorBar(index, sectorTime and (sectorColor(sectorTime, liveBest.sectors[index], previousTime) or colors.text) or nil)
            end
        end
    end
    -- Difference of a sector against the chosen reference (best sector or previous lap)
    local function showSectorDifference(row, sectorTime, bestTime, previousTime, sectorsValid)
        local reference = compareWithPrevious and previousTime or bestTime
        if sectorTime and reference and sectorsValid ~= false then
            local difference = sectorTime - reference
            panel.setCell(row, 3, formatSignedDifference(difference), math.abs(difference) < 0.0005 and colors.dim or (difference < 0 and colors.gain or colors.loss))
        else panel.setCell(row, 3, '', colors.dim) end
    end
    if heldLap then
        local label, labelColor = singleLap and panelTexts.stage or (panelTexts.lap .. heldLap.lapNumber), colors.title
        if heldLap.isFinal then
            label, labelColor = panelTexts.finish, colors.text
            local notices = race.notices or {}
            if #notices > 0 then
                race.noticesShownSince = race.noticesShownSince or os.clock()
                local elapsed = os.clock() - race.noticesShownSince
                local noticeIndex = elapsed < 8 and (math.floor(elapsed / 0.6) % (#notices + 1)) or 1
                if noticeIndex > 0 then label, labelColor = notices[noticeIndex].text, colors[notices[noticeIndex].color] end
            end
        end
        panel.setCell(1, 1, label, labelColor)
        -- Stages (one lap): some start the game's lap clock at a gate after a run-up, so the stage shows the
        -- event time (what counts), against your best total of the event
        local stageTime = singleLap and (race.eventFinalTime or race.eventTime)
        if stageTime and stageTime > heldLap.time + 0.5 then
            local record = race.event and modState.eventRecordTimes and modState.eventRecordTimes[race.event.id]
            panel.setCell(1, 2, formatTime(stageTime), (record and stageTime < record) and colors.best or colors.text)
            if record and not differenceRow then
                panel.setCell(1, 3, formatSignedDifference(stageTime - record), stageTime < record and colors.gain or colors.loss)
            else panel.setCell(1, 3, '', colors.dim) end
        else
            panel.setCell(1, 2, formatTime(heldLap.time), heldLap.isNewBest and colors.best or colors.text)
            if heldLap.best and not differenceRow then
                panel.setCell(1, 3, formatSignedDifference(heldLap.time - heldLap.best), heldLap.time < heldLap.best and colors.gain or colors.loss)
            else panel.setCell(1, 3, '', colors.dim) end
        end
        for index = 1, sectorCount do
            local sectorTime = heldLap.sectorTimes[index]
            panel.setCell(panel.sectorRow(index), 1, 'S' .. index, colors.label)
            panel.setCell(panel.sectorRow(index), 2, sectorTime and string.format('%.3f', sectorTime) or '--', heldLap.sectorColors[index] or colors.dim)
            showSectorDifference(panel.sectorRow(index), sectorTime, heldLap.bestSectorTimes[index],
                heldLap.previousSectorTimes and heldLap.previousSectorTimes[index], heldLap.sectorsValid)
        end
    else
        local liveLap = race.liveLap
        local running = liveLap.running and liveLap.startTime
        panel.setCell(1, 1, running and (singleLap and panelTexts.stage or (panelTexts.lap .. (race.lapNumber + 1))) or panelTexts.start, colors.title)
        local runningTime = running and math.max(0, now - liveLap.startTime - bonusData.between(race, liveLap.startTime, now))
        if singleLap and race.eventTime and race.eventTime > 0 then runningTime = race.eventTime end   -- stages: from the start
        panel.setCell(1, 2, runningTime and formatRunningTime(runningTime) or '--', colors.text)
        panel.setCell(1, 3, '', colors.dim)
        for index = 1, sectorCount do
            panel.setCell(panel.sectorRow(index), 1, 'S' .. index, colors.label)
            local sectorTime = running and liveLap.sectorTimes[index]
            local previousTime = race.previousSectorTimes and race.previousSectorTimes[index]
            if sectorTime then
                local comparedPrevious = (not liveIsStartLap) and previousTime or nil
                panel.setCell(panel.sectorRow(index), 2, string.format('%.3f', sectorTime), sectorColor(sectorTime, liveBest.sectors[index], comparedPrevious) or colors.text)
                showSectorDifference(panel.sectorRow(index), sectorTime, liveBest.sectors[index], comparedPrevious)
            else
                panel.setCell(panel.sectorRow(index), 2, (settings.showPreviousSectors and previousTime) and string.format('%.3f', previousTime) or '--', colors.dim)
                panel.setCell(panel.sectorRow(index), 3, '', colors.dim)
            end
        end
    end
    local row = panel.rowOf('last_lap')
    if row then
        panel.setCell(row, 1, panelTexts.last, colors.label)
        if race.lastLap then
            panel.setCell(row, 2, formatTime(race.lastLap.time), colors.text)
            if race.lastLap.best then
                panel.setCell(row, 3, formatSignedDifference(race.lastLap.time - race.lastLap.best), race.lastLap.time < race.lastLap.best and colors.gain or colors.loss)
            else panel.setCell(row, 3, '', colors.dim) end
        else
            panel.setCell(row, 2, '--', colors.dim); panel.setCell(row, 3, '', colors.dim)
        end
    end
    row = panel.rowOf('best_lap')
    if row then
        panel.setCell(row, 1, panelTexts.best, colors.label)
        panel.setCell(row, 2, best.lap and formatTime(best.lap) or '--', best.lap and colors.best or colors.dim)
        panel.setCell(row, 3, '', colors.dim)
    end
    row = panel.rowOf('ideal_lap')
    if row then
        local idealLap = 0
        for index = 1, sectorCount do
            if not best.sectors[index] then idealLap = nil; break end
            idealLap = idealLap + best.sectors[index]
        end
        panel.setCell(row, 1, panelTexts.ideal, colors.label)
        panel.setCell(row, 2, idealLap and formatTime(idealLap) or '--', idealLap and colors.text or colors.dim)
        -- During a lap: what you have left so far against your best sectors (the ideal); if not, ideal - best lap
        local lost, liveLap = nil, race.liveLap
        if liveLap and liveLap.running and #(liveLap.sectorTimes or {}) > 0 then
            lost = 0
            for index, sectorTime in ipairs(liveLap.sectorTimes) do
                if not liveBest.sectors[index] then lost = nil; break end
                lost = lost + sectorTime - liveBest.sectors[index]
            end
        end
        if lost then panel.setCell(row, 3, formatSignedDifference(lost), lost <= 0 and colors.gain or colors.loss)
        else panel.setCell(row, 3, (idealLap and best.lap) and formatSignedDifference(idealLap - best.lap) or '', colors.dim) end
    end
    row = panel.rowOf('speeds')
    if row then
        local liveLap, reference = race.liveLap, race.bestLapSpeeds
        local top, minimum = liveLap and liveLap.top, liveLap and liveLap.minimum
        if not (liveLap and liveLap.running and top) and race.lastLapSpeeds then top, minimum = race.lastLapSpeeds.top, race.lastLapSpeeds.minimum end
        panel.setCell(row, 1, panelTexts.top, colors.label)
        panel.setCell(row, 2, top and string.format('%.0f', top) or '--', top and ((reference and top >= reference.top) and colors.gain or colors.text) or colors.dim)
        panel.setCell(row, 3, minimum and (panelTexts.minimum .. string.format('%.0f', minimum)) or '',
            minimum and ((reference and reference.minimum and minimum >= reference.minimum) and colors.gain or colors.text) or colors.dim)
    end
    -- Event total and target: how much you need per lap in the laps that are left. The target is the fastest of
    -- your friends' best time (if one beats you), your record and the game's #1
    local total = race.eventEnded and race.eventFinalTime or race.eventTime
    local target = race.target and {time = race.target.time, label = panelTexts.number1} or nil
    if isArcadeRace(race) then
        local id = race.event.id
        local record = modState.eventRecordTimes and modState.eventRecordTimes[id]
        local gameRecord = modState.gameRecords and modState.gameRecords[id]
        if gameRecord and gameRecord.time and (not record or gameRecord.time < record) then record = gameRecord.time end
        if record and (not target or record < target.time) then target = {time = record, label = panelTexts.record} end
        local rival = rivals[id]
        if rival and (not target or rival.time < target.time) then target = {time = rival.time, label = (rival.pilot ~= '' and rival.pilot or '?'):upper():sub(1, 9)} end
    end
    row = panel.rowOf('event_total')
    if row then
        panel.setCell(row, 1, panelTexts.total, colors.label)
        panel.setCell(row, 2, total and formatTime(total) or '--', race.eventEnded and colors.text or colors.dim)
        if target and total and race.eventEnded then
            panel.setCell(row, 3, formatSignedDifference(total - target.time), total <= target.time and colors.gain or colors.loss)
        else panel.setCell(row, 3, '', colors.dim) end
    end
    -- Forecast: at your pace, the total you would finish with (the lap in progress by its live difference,
    -- the ones left at your best lap of this race or, if not yet, your best). Not in Precision events: the
    -- game takes time off the total there, so the laps do not add up to it.
    row = panel.rowOf('forecast')
    if row then
        panel.setCell(row, 1, panelTexts.forecast, colors.label)
        local forecast
        local lapsLeft = race.lapCount and (race.lapCount - race.lapNumber) or nil
        local isPrecision = race.event and race.event.id and race.event.id:find('_PRE_') ~= nil
        if not race.eventEnded and not isPrecision and lapsLeft and lapsLeft >= 1 and race.liveLap and race.liveLap.running then
            local ghost = ghosts[race.ghostKey or '']
            local pace = race.sessionBestLap or best.lap
            local currentLap = (ghost and race.liveDifference) and (ghost.lapTime + race.liveDifference) or (liveBest.lap or pace)
            if currentLap and (lapsLeft == 1 or pace) then forecast = (race.lapTimesSum or 0) + currentLap + (lapsLeft - 1) * (pace or 0) end
        end
        panel.setCell(row, 2, forecast and formatTime(forecast) or '--', forecast and colors.text or colors.dim)
        if forecast and target then panel.setCell(row, 3, formatSignedDifference(forecast - target.time), forecast <= target.time and colors.gain or colors.loss)
        else panel.setCell(row, 3, '', colors.dim) end
    end
    row = panel.rowOf('target')
    if row then
        panel.setCell(row, 1, target and target.label or panelTexts.target, colors.label)
        panel.setCell(row, 2, target and formatTime(target.time) or '--', target and colors.text or colors.dim)
        local lapsLeft = race.lapCount and (race.lapCount - race.lapNumber) or nil
        if singleLap and target and total and race.eventEnded then
            panel.setCell(row, 3, formatSignedDifference(total - target.time), total <= target.time and colors.gain or colors.loss)
        elseif target and lapsLeft and lapsLeft > 1 and not race.eventEnded then
            local neededPerLap = (target.time - (race.lapTimesSum or 0)) / lapsLeft
            panel.setCell(row, 3, string.format('%.2f', neededPerLap) .. panelTexts.perLap, (best.lap and neededPerLap >= best.lap) and colors.gain or colors.worse)
        elseif target and lapsLeft == 1 and not race.eventEnded and not singleLap then
            local neededPerLap = target.time - (race.lapTimesSum or 0)
            panel.setCell(row, 3, string.format('%.2f', neededPerLap) .. panelTexts.perLap, (best.lap and neededPerLap >= best.lap) and colors.gain or colors.worse)
        else panel.setCell(row, 3, '', colors.dim) end
    end
end

-- The game's records: the Arcade menu has one ArcadeEntryVM per event with its leaderboard
-- (LeaderboardEntries) and your entry marked with bIsLocalPlayer. Only numbers and references to game
-- assets are read; the names come from the event definition (an asset).
-- game_records.txt: id \t time \t attempts \t name \t planet \t date \t target \t category \t planet_codename
local GAME_RECORDS_PATH = modFile('game_records.txt')
local gameRecords, gameRecordsFileText = {}, nil
local function loadGameRecords()
    local file = io.open(GAME_RECORDS_PATH, 'r')
    if not file then return end
    local lines = {}
    for line in file:lines() do
        lines[#lines + 1] = line
        local id, time, attempts, eventName, planet, rest = line:match('^([^\t]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$')
        if id and tonumber(time) then
            local date, target, category, planetCodename = (rest or ''):match('^([^\t]*)\t?([%d%.]*)\t?(%d*)\t?([%w_]*)')
            gameRecords[id] = {time = tonumber(time), attempts = tonumber(attempts) or 0, name = eventName or '', planet = planet or '',
                date = date or rest or '', target = tonumber(target), category = tonumber(category), planetCodename = planetCodename or ''}
        end
    end
    file:close()
    gameRecordsFileText = table.concat(lines, '\n') .. '\n'   -- only rewritten if something changes (time, #1, name or category)
end
loadGameRecords()
modState.gameRecords = gameRecords
local eventNameCache = {}
local eventNamesReadThisSession = {}   -- events whose name was already read this session (in case you change the game's language)
-- Objects that are never read: templates (Default__) and leftovers from reloads
local function isLiveObject(object)
    if not isValid(object) then return false end
    local objectName = fullName(object)
    return objectName ~= '' and not objectName:find('Default__', 1, true) and not objectName:find('TRASH_', 1, true) and not objectName:find('REINST_', 1, true)
end
-- Type of a property by its name, looking in the class and its parents (remembered per class)
local propertyTypeCache = {}
local function propertyTypeOf(object, key)
    local classOk, class = pcall(function() return object:GetClass() end)
    if not classOk or not isValid(class) then return nil end
    local cacheKey = fullName(class) .. '|' .. key
    if propertyTypeCache[cacheKey] ~= nil then return propertyTypeCache[cacheKey] or nil end
    local found = false
    pcall(function()
        local currentClass = class
        for _ = 1, 10 do
            if not isValid(currentClass) or found then break end
            currentClass:ForEachProperty(function(property)
                local nameOk, propertyName = pcall(function() return property:GetFName():ToString() end)
                if nameOk and propertyName == key then found = propertyTypeName(property); return true end
            end)
            currentClass = currentClass:GetSuperStruct()
        end
    end)
    propertyTypeCache[cacheKey] = found
    return found or nil
end
local TEXT_PROPERTY_TYPES = {TextProperty = true, StrProperty = true, NameProperty = true}
-- Only read if the property exists and really is a text
local function readAssetText(object, keys)
    if not isLiveObject(object) then return '' end
    for _, key in ipairs(keys) do
        local propertyType = propertyTypeOf(object, key)
        if propertyType and TEXT_PROPERTY_TYPES[propertyType] then
            local readOk, value = pcall(function() return object[key] end)
            if readOk and value ~= nil then
                local textReadOk, text = pcall(function() return value:ToString() end)
                if textReadOk and type(text) == 'string' and text ~= '' and #text < 200 then return text end
            end
        end
    end
    return ''
end
readSafeText = function(object, key) return readAssetText(object, {key}) end
-- Planet codes in the event names and the game's internal codename of each planet
local PLANET_CODENAMES = {DAL = 'Dalmatian', MAS = 'Mastiff', COR = 'Corgi', SPA = 'Spaniel', HSK = 'Husky', WHP = 'Whippet', BGL = 'Beagle'}
-- Name, planet, planet codename and category of an event definition (remembered per event)
local function readEventNames(eventDefinition)
    local key = fullName(eventDefinition)
    if eventNameCache[key] then local cached = eventNameCache[key]; return cached[1], cached[2], cached[3], cached[4] end
    local eventName = readAssetText(eventDefinition, {'PlayerFacingName'})
    local planet = ''
    local trackOk, trackDefinition = pcall(function() return eventDefinition.TrackDef end)
    -- The track keeps its planet as a path (SoftObject), which is not read: the codename comes from the
    -- path of the track itself (.../Planets/Dalmatian/...) and the name from the PlanetDef the game has loaded.
    local planetCodename = trackOk and isLiveObject(trackDefinition) and fullName(trackDefinition):match('/Planets/([%w_]+)/') or ''
    if planetCodename == '' then   -- podracing tracks are not under a planet: it comes from the event code (EVT_ARC_TT_PLANE_BGL_...)
        local planetCode = (fullName(eventDefinition):match('([%w_]+)$') or ''):match('^EVT_ARC_%u+_%u+_(%u%u%u)_')
        planetCodename = PLANET_CODENAMES[planetCode or ''] or ''
    end
    if planetCodename ~= '' then
        local findOk, planetDefinition = pcall(StaticFindObject, '/Game/Griffin/Gameplay/Config/Planets/PLA_' .. planetCodename .. '.PLA_' .. planetCodename)
        if findOk and isLiveObject(planetDefinition) then
            planet = readAssetText(planetDefinition, {'PlayerFacingName', 'DisplayName', 'PlanetName', 'Title'})
        end
    end
    -- If the game has not loaded the podracing planet, Tatooine from its code (BGL)
    if planet == '' and planetCodename == 'Beagle' then planet = 'Tatooine' end
    local category
    local categoryType = propertyTypeOf(eventDefinition, 'Category')
    if categoryType == 'EnumProperty' or categoryType == 'ByteProperty' then
        local readOk, value = pcall(function() return eventDefinition.Category end)
        if readOk and type(value) == 'number' then category = value end
    end
    eventName = eventName:gsub('[\t\r\n]', ' '); planet = planet:gsub('[\t\r\n]', ' ')
    eventNameCache[key] = {eventName, planet, planetCodename, category}
    return eventName, planet, planetCodename, category
end
local function readGameRecords()
    local entryViewModels = FindAllOf('ArcadeEntryVM')
    if not entryViewModels or #entryViewModels == 0 then return end
    local changedCount = 0
    for _, entryViewModel in ipairs(entryViewModels) do
        pcall(function()
            if not isLiveObject(entryViewModel) then return end
            local leaderboard = entryViewModel.LeaderboardDef
            if not isLiveObject(leaderboard) then return end
            local id = leaderboard:GetFName():ToString()
            if not id:find('^LDB_ARC_') then return end
            local entries = entryViewModel.LeaderboardEntries
            if typeName(entries) ~= 'TArray' or #entries == 0 or #entries > 200 then return end
            local myTime, firstPlaceTime
            local authoredOk, authoredEntries = pcall(function() return leaderboard.AuthoredEntries end)
            if authoredOk and typeName(authoredEntries) == 'TArray' and #authoredEntries > 0 and #authoredEntries <= 50 then
                authoredEntries:ForEach(function(_, element)
                    local readOk, seconds = pcall(function() return element:get().TimeSeconds end)
                    if readOk and type(seconds) == 'number' and seconds > 0 and seconds < 36000 and (not firstPlaceTime or seconds < firstPlaceTime) then
                        firstPlaceTime = seconds
                    end
                end)
            end
            entries:ForEach(function(_, element)
                local entry = element:get()
                local seconds = entry.RawStatValue
                if type(seconds) == 'number' and seconds > 0 and seconds < 36000 then
                    if entry.bIsAuthoredTime == true then
                        if not firstPlaceTime or seconds < firstPlaceTime then firstPlaceTime = seconds end   -- the #1 time set by the game
                    elseif entry.bIsLocalPlayer == true then myTime = seconds end
                end
            end)
            if not myTime then return end
            local attempts = entryViewModel.NumberOfAttempts
            attempts = type(attempts) == 'number' and attempts or 0
            local previous = gameRecords[id]
            local isNewTarget = firstPlaceTime and (not previous or not previous.target or math.abs(previous.target - firstPlaceTime) > 0.0005)
            if not previous or math.abs(previous.time - myTime) > 0.0005 or (previous.attempts or 0) < attempts or previous.name == ''
                or not eventNamesReadThisSession[id] or isNewTarget then
                local eventName, planet, planetCodename, category = '', '', '', nil
                local eventDefinition = entryViewModel.EventDef
                if isLiveObject(eventDefinition) and not safeMode.blocked.event_names and not eventNamesReadThisSession[id] then
                    eventNamesReadThisSession[id] = true
                    local readOk, readName, readPlanet, readCodename, readCategory = runGuarded('event_names', readEventNames, eventDefinition)
                    if readOk then eventName, planet, planetCodename, category = readName or '', readPlanet or '', readCodename or '', readCategory end
                end
                local sameTime = previous and math.abs(previous.time - myTime) <= 0.0005
                gameRecords[id] = {time = myTime, attempts = math.max(attempts, previous and previous.attempts or 0),
                    name = eventName ~= '' and eventName or (previous and previous.name or ''),
                    planet = planet ~= '' and planet or (previous and previous.planet or ''), target = firstPlaceTime or (previous and previous.target),
                    category = category or (previous and previous.category),
                    planetCodename = planetCodename ~= '' and planetCodename or (previous and previous.planetCodename or ''),
                    date = (sameTime and previous.date ~= '') and previous.date or os.date('%Y-%m-%d %H:%M')}
                if not sameTime then changedCount = changedCount + 1 end
            end
        end)
    end
    local ids = {}
    for id in pairs(gameRecords) do ids[#ids + 1] = id end
    table.sort(ids)
    local lines = {}
    for _, id in ipairs(ids) do
        local record = gameRecords[id]
        lines[#lines + 1] = string.format('%s\t%.3f\t%d\t%s\t%s\t%s\t%s\t%s\t%s', id, record.time, record.attempts or 0, record.name or '', record.planet or '',
            record.date or '', record.target and string.format('%.3f', record.target) or '', record.category and tostring(record.category) or '',
            record.planetCodename or '')
    end
    local text = table.concat(lines, '\n') .. '\n'
    if text ~= gameRecordsFileText then
        writeFile(GAME_RECORDS_PATH, text, 'w')
        log(string.format('Récords del juego importados: %d eventos (%d nuevos o mejorados)', #ids, changedCount))
        gameRecordsFileText = text
    end
end
local function readGameRecordsWhenIdle()
    if modState.race and not modState.race.eventEnded then return end
    local now = os.clock()
    if modState.gameRecordsReadAt and now < modState.gameRecordsReadAt then return end
    modState.gameRecordsReadAt = now + 4
    if safeMode.blocked.game_records then return end
    local ok, err = runGuarded('game_records', readGameRecords)
    if not ok and tostring(err) ~= modState.gameRecordsError then
        log('No se pudieron leer los récords del juego: ' .. tostring(err)); modState.gameRecordsError = tostring(err)
    end
end

local function tick()
    readGameRecordsWhenIdle()
    local playerController = findLocalPlayerController()
    if not isValid(playerController) or not isValid(playerController.Pawn) then
        modState.missingVehicleTicks = modState.missingVehicleTicks + 1
        if modState.missingVehicleTicks > 150 then endRace('sin vehículo') end   -- ~3 s
        return
    end
    modState.missingVehicleTicks = 0
    local controlDown = playerController:IsInputKeyDown(KEYS.leftControl) == true or playerController:IsInputKeyDown(KEYS.rightControl) == true
    local recordingChordDown = controlDown and playerController:IsInputKeyDown(KEYS.f9) == true
    if recordingChordDown and not modState.recordingChordDown then
        modState.recordingEnabled = not modState.recordingEnabled
        log(modState.recordingEnabled and 'Grabación reanudada' or 'Grabación en pausa')
        if not modState.recordingEnabled then endRace('pausa') end
    end
    modState.recordingChordDown = recordingChordDown
    local panelChordDown = controlDown and playerController:IsInputKeyDown(KEYS.f10) == true
    if panelChordDown and not modState.panelChordDown then
        modState.timingPanelVisible = not modState.timingPanelVisible
        log(modState.timingPanelVisible and 'Panel de tiempos visible' or 'Panel de tiempos oculto')
    end
    modState.panelChordDown = panelChordDown
    modState.ticks = modState.ticks + 1
    if not modState.recordingEnabled or safeMode.blocked.recording then return end
    local gameState = findGameState(playerController)
    local route = findActiveRoute(playerController, gameState)
    if not route then endRace('sin ruta activa'); return end
    local key = tostring(address(playerController:GetWorld())) .. '|' .. tostring(address(route))
    local race = modState.race
    if not race or race.key ~= key or not isValid(race.route) then
        endRace('cambio de circuito')
        if safeMode.blocked.race_hook then return end
        -- Arcade only (0.9.29): nothing is recorded or shown in other modes (campaign, online...).
        -- The event can take a moment to be readable, so a race is given up after 5 s without one.
        if modState.skippedRace and modState.skippedRace.key == key and modState.skippedRace.logged then return end
        local eventOk, eventInfo = pcall(readEventInfo, gameState)
        local eventId = eventOk and eventInfo and eventInfo.id
        if not (eventId and eventId:find('^LDB_ARC')) then
            local skip = modState.skippedRace
            if not skip or skip.key ~= key then modState.skippedRace = {key = key, since = os.clock()}; return end
            if not skip.logged and os.clock() - skip.since > 5 then
                skip.logged = true
                log('Carrera fuera del Arcade (' .. tostring(eventId or 'sin evento') .. '): no se graba ni se muestra el panel')
            end
            return
        end
        local created, newRace = runGuarded('race_hook', function()
            local createdRace = createRace(playerController, gameState, route, key)
            createdRace.raceComponent = findRaceComponent(playerController)
            return createdRace
        end)
        if not created then error(newRace, 0) end
        modState.race = newRace
        -- 0.9.29: the ghost is made now, while the circuit loads, so the start does not stutter
        if GHOST_ENABLED and not safeMode.blocked.race_ghost then
            local ghostOk, ghostError = runGuarded('race_ghost', startRaceGhost, newRace, playerController.Pawn)
            if not ghostOk then log('Fantasma: falló: ' .. tostring(ghostError)) end
        end
        return
    end
    if race.pendingGhost and os.clock() >= race.pendingGhost.nextTry then
        local placeOk, placeError = runGuarded('race_ghost', placePendingGhost, race, playerController.Pawn)
        if not placeOk then log('Fantasma: falló: ' .. tostring(placeError)); race.pendingGhost = nil end
    end
    if race.nextRouteSample then sampleRouteStep(race); return end
    recordSample(race, playerController)
    local ok, err = pcall(updateTimingPanel, playerController, race)
    if not ok then
        if tostring(err) ~= modState.timingPanelError then log('Panel de tiempos desactivado por un error (se reintenta cada 5 s): ' .. tostring(err)) end
        modState.timingPanelError = tostring(err)
        if modState.timingPanel then pcall(modState.timingPanel.close); modState.timingPanel = nil end
        modState.timingPanelRetryAt = os.clock() + 5
    end
end

if _G.SWGRTelemetry and _G.SWGRTelemetry.stop then pcall(_G.SWGRTelemetry.stop) end
local modControl = {running = true, lastError = nil, retryAt = 0}
function modControl.stop() modControl.running = false; endRace('recarga') end
_G.SWGRTelemetry = modControl
LoopInGameThreadWithDelay(SAMPLE_INTERVAL_MS, function()
    if not modControl.running or os.clock() < modControl.retryAt then return end
    local ok, err = xpcall(tick, debug.traceback)
    if not ok then
        if err ~= modControl.lastError then log('ERROR ' .. tostring(err)) end
        modControl.lastError = err
        modControl.retryAt = os.clock() + 2
        local now = os.clock()
        modControl.errorTimes = modControl.errorTimes or {}
        table.insert(modControl.errorTimes, now)
        while modControl.errorTimes[1] and now - modControl.errorTimes[1] > 120 do table.remove(modControl.errorTimes, 1) end
        if #modControl.errorTimes >= 10 and not safeMode.blocked.recording then
            pcall(endRace, 'modo seguro')
            if modState.timingPanel then pcall(modState.timingPanel.close); modState.timingPanel = nil end
            blockOperation('recording', 'session', 'demasiados errores seguidos: ' .. tostring(err):match('^[^\n]*'))
        end
    end
end)


log('READY v' .. VERSION .. '. Ctrl+F9 pausa/reanuda la grabación, Ctrl+F10 muestra/oculta el panel. Archivos en la carpeta del mod.')
