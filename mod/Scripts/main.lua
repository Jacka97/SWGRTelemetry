-- SWGR Telemetry v0.9.28 (read only, for offline use)
-- Records position, speed and progress along the track's route; measures sectors between the
-- game's checkpoints and uses the official lap time (PlayerRaceEventComponent.PreviousLapTime)
-- for laps and records.
-- It never writes to game objects and never hooks game functions: it only reads.
-- Data sources taken from N0M4D's MiniMap and LapRecord.
-- Shortcuts: Ctrl+F9 pauses/resumes recording · Ctrl+F10 shows/hides the timing panel ·
-- Ctrl+Shift+K searches the game for where it keeps your records (writes record_search.txt).

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
    logs = {'log.txt', 'diagnostics.txt', 'safe_mode.txt', 'operation_in_progress.txt', 'record_search.txt', 'record_search_progress.txt', 'state_samples.txt'},
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
-- Ghost (0.9.29): the in-race ghost; its trail is paused (two crashes around the ramjet) and the vehicle
-- state diagnostics read only the vehicle state (logs\state_samples.txt)
local GHOST_ENABLED, TRAIL_ENABLED, STATE_WATCH_ENABLED = true, false, true
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
local function log(message)
    local line = '[SWGRTelemetry] ' .. tostring(message)
    print(line .. '\n')
    loggedLineCount = loggedLineCount + 1
    if loggedLineCount > 3000 then return end
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
-- Moto: EnergyBrakeState / EnergyBrakeCharge (aún sin confirmar). Todos: Brake.
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
-- La moto todavía no marca W: falta confirmar qué campo es el bueno.
function vehicleStateData.trailCode(vehicleType, values)
    if next(values) == nil then return '' end
    local isActive, white = vehicleStateData.isActive, false
    if vehicleType == 'CAR' then white = isActive(values.Drifting)
    elseif vehicleType == 'SKIMMER' then white = isActive(values.Knifing)
    elseif vehicleType == 'PLANE' then white = isActive(values.AirBrakeScale)
    end
    local code = (white and 'W' or '') .. (isActive(values.Brake) and 'B' or '')
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
    record_search = 'la búsqueda de récords (Ctrl+Shift+K)', race_hook = 'engancharse a la carrera', recording = 'la grabación',
    event_names = 'leer los nombres de evento del juego', race_ghost = 'el fantasma en pista', ghost_look = 'el aspecto del fantasma', ghost_vehicle = 'copiar tu vehículo para el fantasma', state_watch = 'el diagnóstico de estados del vehículo', ghost_trail = 'la estela del fantasma'}
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
    elseif modState.longGuard then writeFile(OPERATION_IN_PROGRESS_PATH, modState.longGuard .. '\n', 'w')
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

local checkEventEnd, writeDiagnostics, updateEventRecord

-- Ghost of the best lap (ghosts.txt): distance covered in the lap (cm) and the time at that point,
-- every ~10 m. Used for the live difference on the timing panel.
local GHOSTS_PATH = modFile('ghosts.txt')
local ghosts = {}
local ghostsHaveOldKeys = false
do
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
            ghost.distances[#ghost.distances + 1] = point.distance; ghost.times[#ghost.times + 1] = point.time - origin
            lastDistance = point.distance
        end
    end
    if #ghost.distances < 10 then return end
    ghosts[key] = ghost
    saveGhosts()
end

-- Diagnostics: dumps the game's race properties (the player's race component, the race state and
-- the event data) to diagnostics.txt, to find how many laps the event has and when it ends.
local DIAGNOSTICS_PATH = modFile('diagnostics.txt')
writeDiagnostics = function(race, label)
    local lines = {'== ' .. os.date('%H:%M:%S') .. ' ' .. label .. ' | vueltas ' .. tostring(race.lapNumber)}
    local function dump(title, object)
        if not isValid(object) then lines[#lines + 1] = title .. ': no disponible'; return end
        lines[#lines + 1] = title .. ': ' .. fullName(object)
        local ok, err = pcall(function()
            local class, seenClasses = object:GetClass(), {}
            for _ = 1, 8 do
                if not isValid(class) then break end
                local className = fullName(class)
                if seenClasses[className] or className:find('/Script/Engine.', 1, true) or className:find('/Script/CoreUObject.', 1, true) then break end
                seenClasses[className] = true
                local count = 0
                class:ForEachProperty(function(property)
                    count = count + 1
                    if count > 200 then return true end
                    local key = property:GetFName():ToString()
                    local readOk, value = pcall(function() return object[key] end)
                    local text
                    if not readOk then text = '?'
                    else
                        local luaType = type(value)
                        if luaType == 'number' or luaType == 'boolean' or luaType == 'string' or luaType == 'nil' then text = tostring(value)
                        else
                            local valueType = typeName(value)
                            if valueType == 'FName' or valueType == 'FString' or valueType == 'FText' then
                                local textReadOk, valueText = pcall(function() return value:ToString() end)
                                text = textReadOk and ('"' .. valueText .. '"') or valueType
                            elseif valueType == 'TArray' then text = 'lista[' .. #value .. ']'
                            elseif (valueType == 'UObject' or valueType == 'AActor') and isValid(value) then text = fullName(value)
                            else text = valueType end
                        end
                    end
                    lines[#lines + 1] = '  ' .. key .. ' = ' .. text:sub(1, 160)
                end)
                class = class:GetSuperStruct()
            end
        end)
        if not ok then lines[#lines + 1] = '  error: ' .. tostring(err) end
    end
    dump('PlayerRaceEventComponent', race.raceComponent)
    dump('RacingGameState', race.gameState)
    dump('RaceEventViewModel', readProperty(race.gameState, 'RaceEventViewModel'))
    writeFile(DIAGNOSTICS_PATH, table.concat(lines, '\n') .. '\n')
end

-- Searches the game for objects that look like records, leaderboards or saved games, and dumps
-- their data to record_search.txt. It can freeze the game for a few seconds.
-- Safety (v0.9.3): the TYPE of each field is checked before reading it. In live data only numbers,
-- booleans and names are read (a record time is a number); texts are not read, because copying a
-- text from a half-destroyed object is what closed the game in v0.9.2.
local NUMERIC_PROPERTY_TYPES = {FloatProperty = 1, DoubleProperty = 1, IntProperty = 1, Int64Property = 1, UInt32Property = 1,
    UInt64Property = 1, Int16Property = 1, UInt16Property = 1, Int8Property = 1, ByteProperty = 1,
    BoolProperty = 1, EnumProperty = 1, NameProperty = 1}
local RECORD_SEARCH_PROGRESS_PATH = modFile('record_search_progress.txt')
local function propertyTypeName(property)
    local ok, result = pcall(function() return property:GetClass():GetFName():ToString() end)
    return ok and result or '?'
end
local function scalarToText(value)
    local luaType = type(value)
    if luaType == 'number' or luaType == 'boolean' or luaType == 'string' or luaType == 'nil' then return tostring(value) end
    if typeName(value) == 'FName' then
        local ok, text = pcall(function() return value:ToString() end); return ok and text or 'FName'
    end
    return typeName(value)
end
local function dumpFields(lines, holder, struct, indent, depth, allowTexts)
    local count = 0
    struct:ForEachProperty(function(property)
        count = count + 1
        if count > 200 then return true end
        local key = property:GetFName():ToString()
        local propertyType = propertyTypeName(property)
        local text
        if NUMERIC_PROPERTY_TYPES[propertyType] then
            local readOk, value = pcall(function() return holder[key] end)
            text = readOk and scalarToText(value) or '?'
        elseif (propertyType == 'StrProperty' or propertyType == 'TextProperty') then
            if allowTexts then
                local readOk, value = pcall(function() return holder[key] end)
                local textReadOk, valueText = false, nil
                if readOk and value ~= nil then textReadOk, valueText = pcall(function() return value:ToString() end) end
                text = textReadOk and ('"' .. tostring(valueText) .. '"') or 'texto'
            else text = '(texto, no se lee)' end
        elseif propertyType == 'StructProperty' then
            text = 'estructura'
            if depth < 3 then
                local structOk, innerStruct = pcall(function() return property:GetStruct() end)
                local readOk, value = pcall(function() return holder[key] end)
                if structOk and readOk and innerStruct and value ~= nil then
                    lines[#lines + 1] = indent .. key .. ' = {'
                    local dumpOk, dumpError = pcall(dumpFields, lines, value, innerStruct, indent .. '  ', depth + 1, allowTexts)
                    if not dumpOk then lines[#lines + 1] = indent .. '  error: ' .. tostring(dumpError) end
                    lines[#lines + 1] = indent .. '}'
                    return
                end
            end
        elseif propertyType == 'ArrayProperty' then
            local innerOk, innerProperty = pcall(function() return property:GetInner() end)
            local itemType = innerOk and innerProperty and propertyTypeName(innerProperty) or '?'
            local readOk, value = pcall(function() return holder[key] end)
            local itemCount = (readOk and typeName(value) == 'TArray') and #value or -1
            text = 'lista[' .. itemCount .. '] de ' .. itemType
            if itemCount > 0 and itemCount <= 64 and NUMERIC_PROPERTY_TYPES[itemType] then
                local items = {}
                pcall(function() value:ForEach(function(index, element)
                    if index > 16 then return true end
                    items[#items + 1] = scalarToText(element:get())
                end) end)
                text = text .. ' ' .. table.concat(items, ', ')
            elseif itemCount > 0 and itemCount <= 64 and itemType == 'StructProperty' and depth < 3 then
                local structOk, innerStruct = pcall(function() return innerProperty:GetStruct() end)
                if structOk and innerStruct then
                    lines[#lines + 1] = indent .. key .. ' = ' .. text
                    pcall(function() value:ForEach(function(index, element)
                        if index > 24 then return true end
                        lines[#lines + 1] = indent .. '  [' .. index .. '] {'
                        local dumpOk, dumpError = pcall(dumpFields, lines, element:get(), innerStruct, indent .. '    ', depth + 1, allowTexts)
                        if not dumpOk then lines[#lines + 1] = indent .. '    error: ' .. tostring(dumpError) end
                        lines[#lines + 1] = indent .. '  }'
                    end) end)
                    return
                end
            end
        elseif propertyType == 'ObjectProperty' or propertyType == 'WeakObjectProperty' or propertyType == 'SoftObjectProperty' then
            if propertyType == 'ObjectProperty' then
                local readOk, value = pcall(function() return holder[key] end)
                text = (readOk and isValid(value)) and fullName(value) or 'objeto'
            else text = propertyType end
        else
            text = propertyType
        end
        lines[#lines + 1] = indent .. key .. ' = ' .. tostring(text):sub(1, 300)
    end)
end
local function dumpObject(lines, title, object, allowTexts)
    if not isValid(object) then lines[#lines + 1] = title .. ': no disponible'; return end
    lines[#lines + 1] = title .. ': ' .. fullName(object)
    local ok, err = pcall(function()
        local class, seenClasses = object:GetClass(), {}
        for _ = 1, 8 do
            if not isValid(class) then break end
            local className = fullName(class)
            if seenClasses[className] or className:find('/Script/Engine.', 1, true) or className:find('/Script/CoreUObject.', 1, true) then break end
            seenClasses[className] = true
            dumpFields(lines, object, class, '  ', 1, allowTexts)
            class = class:GetSuperStruct()
        end
    end)
    if not ok then lines[#lines + 1] = '  error: ' .. tostring(err) end
end

-- Targeted search: the player's saved data (live objects, not game assets), and the definition of
-- the Arcade event and of its leaderboard for the event being raced.
local SEARCH_IGNORED_CLASS_WORDS = {'delegatefunction', 'function', 'slot', 'widget', 'wbp_', 'fuse', 'moviescene', 'material',
    'texture', 'sound', 'metasound', 'blendprofile', 'skeletal', 'staticmesh', 'animsequence', 'niagara',
    'stringtable', 'datatable', 'curve', 'font', 'subsurface', 'physicalmaterial', 'class', 'property',
    'scriptstruct', 'enum', 'package', 'blueprintgeneratedclass', 'recorder'}
local SEARCH_LIVE_CLASS_WORDS = {'save', 'profile', 'progress', 'record', 'arcade', 'leaderboard', 'medal', 'besttime', 'personal', 'stats', 'unlock'}
local SEARCH_IGNORED_NAME_WORDS = {'trash_', 'reinst_', 'skel_', 'placeholder', 'hotreload'}

local function searchGameForRecords()
    local startedAt = os.clock()
    local outputPath = modFile('record_search.txt')
    local lines = {'== Búsqueda de récords v3 ' .. os.date('%Y-%m-%d %H:%M:%S')}
    local eventKey
    if modState.race and modState.race.event and modState.race.event.id then eventKey = modState.race.event.id:gsub('^LDB_ARC_', '') end
    eventKey = eventKey or 'TT_BIKE_DAL_A_SHORT_01'
    lines[#lines + 1] = 'Evento buscado: ' .. eventKey
    writeFile(RECORD_SEARCH_PROGRESS_PATH, os.date('%H:%M:%S') .. ' recorriendo objetos\n', 'w')
    local liveObjects, definitions, liveClassCounts, objectCount = {}, {}, {}, 0
    local iterationOk = pcall(function()
        ForEachUObject(function(object)
            objectCount = objectCount + 1
            local nameOk, objectName = pcall(function() return object:GetFullName() end)
            if not nameOk or not objectName then return end
            local className = objectName:match('^(%S+)') or ''
            local lowerClass, lowerName = className:lower(), objectName:lower()
            if lowerName:find('default__', 1, true) then return end
            for _, word in ipairs(SEARCH_IGNORED_NAME_WORDS) do if lowerName:find(word, 1, true) then return end end
            for _, word in ipairs(SEARCH_IGNORED_CLASS_WORDS) do if lowerClass:find(word, 1, true) then return end end
            if lowerName:find(eventKey:lower(), 1, true) and #definitions < 40 then definitions[#definitions + 1] = object end
            local isAsset = objectName:find(' /Game/', 1, true) or objectName:find(' /Griffin', 1, true)
            if not isAsset then
                for _, word in ipairs(SEARCH_LIVE_CLASS_WORDS) do
                    if lowerClass:find(word, 1, true) then
                        liveClassCounts[className] = (liveClassCounts[className] or 0) + 1
                        if #liveObjects < 80 then liveObjects[#liveObjects + 1] = object end
                        return
                    end
                end
            end
        end)
    end)
    if not iterationOk then lines[#lines + 1] = 'ForEachUObject no disponible' end
    lines[#lines + 1] = string.format('Objetos revisados: %d · datos vivos: %d · definiciones del evento: %d · %.1f s',
        objectCount, #liveObjects, #definitions, os.clock() - startedAt)
    lines[#lines + 1] = ''
    lines[#lines + 1] = '-- Clases de datos vivos'
    for className, count in pairs(liveClassCounts) do lines[#lines + 1] = string.format('%5d  %s', count, className) end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '-- Lista de datos vivos (antes de leerlos)'
    for index, object in ipairs(liveObjects) do lines[#lines + 1] = string.format('%3d  %s', index, fullName(object)) end
    -- What is here so far is saved, even if something fails later
    writeFile(outputPath, table.concat(lines, '\n') .. '\n', 'a')
    local function dumpStep(title, object, allowTexts)
        writeFile(RECORD_SEARCH_PROGRESS_PATH, os.date('%H:%M:%S') .. ' leyendo ' .. title .. ' ' .. fullName(object) .. '\n', 'w')
        local stepLines = {''}
        dumpObject(stepLines, title, object, allowTexts)
        writeFile(outputPath, table.concat(stepLines, '\n') .. '\n', 'a')
    end
    writeFile(outputPath, '\n-- Definiciones del evento\n', 'a')
    for index, object in ipairs(definitions) do dumpStep('DEF ' .. index, object, true) end
    writeFile(outputPath, '\n-- Datos vivos (solo números)\n', 'a')
    for index, object in ipairs(liveObjects) do dumpStep('VIVO ' .. index, object, false) end
    writeFile(outputPath, '== fin de la búsqueda\n\n', 'a')
    writeFile(RECORD_SEARCH_PROGRESS_PATH, os.date('%H:%M:%S') .. ' terminado\n', 'w')
    log(string.format('Búsqueda de récords v3: %d datos vivos, %d definiciones (%.1f s). Guardado en record_search.txt',
        #liveObjects, #definitions, os.clock() - startedAt))
end

local function endRace(reason)
    local race = modState.race
    if not race then return end
    if modState.longGuard then
        modState.longGuard = nil
        if #guardedOperationStack == 0 then os.remove(OPERATION_IN_PROGRESS_PATH) end
    end
    if race.stateWatch and #race.stateWatch.lines > 0 then writeFile(modFile('state_samples.txt'), table.concat(race.stateWatch.lines, '\n') .. '\n'); race.stateWatch.lines = {} end
    if race.ghost then local actors = race.ghost.actors or {race.ghost.actor}; race.ghost = nil; for _, actor in ipairs(actors) do pcall(function() if isValid(actor) then actor:K2_DestroyActor() end end) end end
    if race.eventEnded and race.lapNumber > 0 then
        local key = 'laps|' .. trackKey(race)
        if not learnedTracks[key] or race.lapNumber > learnedTracks[key] then
            learnedTracks[key] = race.lapNumber; saveLearnedTracks(); log('Vueltas del evento aprendidas: ' .. race.lapNumber)
        end
    end
    if race.filesDeferred then
        if race.startTime and race.event and race.event.id and race.event.id:find('^LDB_ARC') then
            pcall(updateEventRecord, race, nil)
            log('Carrera cerrada (' .. reason .. '): reinicio rápido, se cuenta el intento sin guardar archivos')
        else
            log('Carrera cerrada (' .. reason .. ') antes de la salida: sin archivos')
        end
    else
        if race.eventEnded or race.lapNumber > 0 or not race.startTime then
            -- finished events count their attempt in finishEvent
        elseif race.event and race.event.id and race.event.id:find('^LDB_ARC') then pcall(updateEventRecord, race, nil) end
        flushTelemetryBuffer(race)
        if race.telemetryPath then log('Carrera cerrada (' .. reason .. '): ' .. race.telemetryPath) end
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
    race.sectorCheckpointOrder, race.sectorNumberOfCheckpoint = order, {}
    for position, index in ipairs(order) do race.sectorNumberOfCheckpoint[index] = position end
end

-- Live checkpoint crossing, for the timing panel.
local function onLiveCheckpointCrossing(race, checkpoint, crossingTime)
    if not race.finishCheckpoint then return end
    local liveLap = race.liveLap
    if checkpoint == race.finishCheckpoint or checkpoint == race.startCheckpoint then
        if not liveLap.running then
            liveLap.running, liveLap.startTime, liveLap.sectorStartTime, liveLap.sectorTimes = true, crossingTime, crossingTime, {}
        end
        return
    end
    if race.usesOfficialSectors then return end   -- the panel uses the game's official sectors
    if liveLap.running and race.sectorNumberOfCheckpoint[checkpoint] == #liveLap.sectorTimes + 1 then
        liveLap.sectorTimes[#liveLap.sectorTimes + 1] = crossingTime - liveLap.sectorStartTime
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
    local sectorsValid = #crossingsInLap == expectedCrossings
    local sectorTimes, previousBoundary = {}, lapStart
    for _, crossing in ipairs(crossingsInLap) do sectorTimes[#sectorTimes + 1] = crossing.time - previousBoundary; previousBoundary = crossing.time end
    sectorTimes[#sectorTimes + 1] = lapEnd - previousBoundary
    local sectorCount = expectedCrossings + 1
    -- The game's official sectors, if there are some for this lap and they add up to its time
    local officialLap = race.usesOfficialSectors and race.officialSectors and race.officialSectors.completed[#race.officialSectors.completed]
    if officialLap and not officialLap.used and #officialLap.sectorTimes == sectorCount and math.abs(officialLap.time - lapTime) < 0.02 then
        officialLap.used = true
        sectorTimes, sectorsValid = {}, true
        for index, value in ipairs(officialLap.sectorTimes) do sectorTimes[index] = value end
        race.lastSectorSource = 'official'
    else
        race.lastSectorSource = 'detected'
    end
    race.lapNumber = race.lapNumber + 1

    local startLap = isStartLap(race, race.lapNumber)
    local key = bestTimesKey(race, sectorCount, startLap)
    -- References: flying laps (flyingBest) and, on the start lap, its S1 and its time (startBest).
    -- Only the S1 of the start lap is different; the rest of lap 1 counts like any other lap.
    local flyingKey = bestTimesKey(race, sectorCount, false)
    local flyingBest = bestTimes[flyingKey] or {sectors = {}}
    local startBest = startLap and (bestTimes[key] or {sectors = {}}) or nil
    local best = {lap = startLap and startBest.lap or flyingBest.lap, sectors = {}}
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
    if lapTime >= MIN_LAP_SECONDS and (not race.sessionBestLap or lapTime < race.sessionBestLap) then race.sessionBestLap = lapTime end
    if sectorsValid and not startLap then race.previousSectorTimes = sectorTimes end
    race.panelBestKey = bestTimesKey(race, sectorCount, false)
    -- Ghost: the fastest lap with a complete trace (if there is none yet, the first official lap)
    local oldGhost = ghosts[key]
    if race.heldLap then race.heldLap.ghostLapTime = oldGhost and oldGhost.lapTime or nil end
    if isArcadeRace(race) and isOfficial and resetCount == 0 and repeatedCrossings == 0 and lapTime >= MIN_LAP_SECONDS and lapTime <= MAX_LAP_SECONDS
        and (not oldGhost or lapTime < oldGhost.lapTime - 1e-4) then
        local liveStart = race.liveLap and race.liveLap.running and race.liveLap.startTime
        pcall(storeGhost, race, key, lapStart, lapEnd, lapTime, (liveStart and liveStart >= lapStart - 0.5 and liveStart < lapEnd) and liveStart or lapStart)
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
    if lapTime >= MIN_LAP_SECONDS and lapTime <= MAX_LAP_SECONDS and (not best.lap or lapTime < best.lap) then
        best.lap = lapTime; improved = true
        if startLap then startBest.lap = lapTime else flyingBest.lap = lapTime end
        writeSummaryLine(race, startLap and '  >> Nueva mejor salida' or '  >> Nueva mejor vuelta')
    end
    if sectorsValid then
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
    if improved and isArcadeRace(race) then saveBestTimes() end
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
    -- the delicate part is the race itself: closing the game on the results screen is not a crash
    if modState.longGuard then
        if race.stateWatch and #race.stateWatch.lines > 0 then writeFile(modFile('state_samples.txt'), table.concat(race.stateWatch.lines, '\n') .. '\n'); race.stateWatch.lines = {} end
        modState.longGuard = nil
        if #guardedOperationStack == 0 then os.remove(OPERATION_IN_PROGRESS_PATH) end
    end
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
        local updateOk, previousTotal = pcall(updateEventRecord, race, total)
        local ghostOk, ghostError = pcall(saveOwnGhost, race, total)
        if not ghostOk then log('Fantasma: no se pudo guardar: ' .. tostring(ghostError)) end
        -- Panel notices: new record (against the mod's and the game's) and #1 beaten
        local previousRecord = updateOk and previousTotal or nil
        local gameRecord = modState.gameRecords and race.event and modState.gameRecords[race.event.id]
        if gameRecord and gameRecord.time and (not previousRecord or gameRecord.time < previousRecord) then previousRecord = gameRecord.time end
        race.notices = {}
        if isArcadeRace(race) and previousRecord and total < previousRecord - 1e-4 then race.notices[#race.notices + 1] = {text = panelTexts.record, color = 'best'} end
        if race.target and total <= race.target.time then race.notices[#race.notices + 1] = {text = panelTexts.beaten, color = 'gain'} end
        if race.historyPath then writeFile(race.historyPath, os.date('%Y-%m-%d %H:%M:%S') .. '\tsession ' .. race.sessionStamp .. '\t' .. line .. '\n') end
    end
    writeDiagnostics(race, 'fin del evento')
end

checkEventEnd = function(race, now)
    local afterFinish = race.afterFinish
    if not afterFinish or race.eventEnded then return end
    -- Speed after the finish line against the speed before: the autopilot goes much slower
    if now >= afterFinish.time + 3 then
        race.afterFinish = nil
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
    pcall(writeDiagnostics, race, 'vuelta ' .. race.lapNumber)
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
-- Trail behind the ghost (0.9.29): thin translucent pieces over the last ~1.5 s of its path, orange
-- with the afterburner, blue with the ramjet, red when braking hard. Nothing in normal driving.
local TRAIL_PIECES, TRAIL_STEP = 15, 0.1
-- Paused (0.9.29): the game closed twice around the ramjet with the trail and the state diagnostics on.
-- The boost is still saved in the ghosts; the trail and the diagnostics come back once fixed.
local hologramMaterial   -- defined below
local TRAIL_COLORS = {A = {1, 0.45, 0.05}, R = {0.2, 0.55, 1}, B = {1, 0.08, 0.05}}
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
-- what the ghost was doing at that moment: boost from the file, braking from its speed
local function ghostStateAt(points, t)
    local from = ghostPointAt(points, t)
    if from.boost == 'A' or from.boost == 'R' then return from.boost end
    -- Fantasmas con columna 9: el freno real. Los anteriores lo deducen de la pérdida de velocidad.
    if from.trail and from.trail ~= '' then return from.trail:find('B') and 'B' or nil end
    local function speedAt(time)
        local a, b = ghostPointAt(points, time - 0.1), ghostPointAt(points, time + 0.1)
        local span = b.t - a.t
        if span <= 0 then return nil end
        return math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) / 100 / span
    end
    local before, after = speedAt(t - 0.15), speedAt(t + 0.15)
    if before and after and (before - after) / 0.3 > 25 then return 'B' end   -- losing more than 25 m/s every second
    return nil
end
local function drawGhostTrail(ghost, elapsed)
    for index, piece in ipairs(ghost.trail) do
        local newer, older = elapsed - (index - 1) * TRAIL_STEP, elapsed - index * TRAIL_STEP
        local state = older > ghost.points[1].t and ghostStateAt(ghost.points, newer) or nil
        if not state or not ghost.trailMaterials[state] then
            if piece.shown then piece.shown = false; piece.actor:SetActorHiddenInGame(true) end
        else
            local a = ghostPositionAt(ghost.points, older, ghost.lift)
            local b = ghostPositionAt(ghost.points, newer, ghost.lift)
            local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
            local length = math.sqrt(dx * dx + dy * dy + dz * dz)
            if length > 1 then
                local width = (state == 'B' and 12 or 25) * (1 - 0.6 * (index - 1) / TRAIL_PIECES)
                piece.actor:K2_SetActorLocationAndRotation({X = (a.X + b.X) / 2, Y = (a.Y + b.Y) / 2, Z = (a.Z + b.Z) / 2},
                    {Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0}, false, {}, true)
                piece.actor:SetActorScale3D({X = length / 100, Y = width / 100, Z = width / 100})
                if piece.state ~= state then piece.state = state; pcall(function() piece.component:SetMaterial(0, ghost.trailMaterials[state]) end) end
                if not piece.shown then piece.shown = true; piece.actor:SetActorHiddenInGame(false) end
            end
        end
    end
end
local function spawnGhostTrail(ghost, pawn, world)
    local actorClass = StaticFindObject('/Script/Engine.StaticMeshActor')
    local cube = StaticFindObject('/Engine/BasicShapes/Cube.Cube')
    if not isValid(cube) and type(LoadAsset) == 'function' then pcall(function() cube = LoadAsset('/Engine/BasicShapes/Cube.Cube') end) end
    if not (isValid(actorClass) and isValid(cube) and isValid(world)) then return 'sin estela (falta la pieza básica)' end
    ghost.trailMaterials = {}
    for state, rgb in pairs(TRAIL_COLORS) do
        local material = hologramMaterial(world, {R = rgb[1], G = rgb[2], B = rgb[3], A = 0.6})
        if material then ghost.trailMaterials[state] = material end
    end
    if not next(ghost.trailMaterials) then return 'sin estela (sin material)' end
    local where = pawn:K2_GetActorLocation()
    ghost.trail = {}
    for _ = 1, TRAIL_PIECES do
        local actor = world:SpawnActor(actorClass, {X = where.X, Y = where.Y, Z = where.Z - 10000}, {Pitch = 0, Yaw = 0, Roll = 0})
        if isValid(actor) then
            local component = readProperty(actor, 'StaticMeshComponent')
            pcall(function() component:SetMobility(2) end)
            pcall(function() component:SetStaticMesh(cube) end)
            pcall(function() component:SetCollisionEnabled(0) end)
            pcall(function() actor:SetActorHiddenInGame(true) end)
            ghost.trail[#ghost.trail + 1] = {actor = actor, component = component, shown = false}
            ghost.actors = ghost.actors or {ghost.actor}
            ghost.actors[#ghost.actors + 1] = actor
        end
    end
    return string.format('estela de %d piezas', #ghost.trail)
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
    if not isValid(ghost.actor) then race.ghost = nil; return end
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
        ghost.actor:K2_SetActorLocationAndRotation(location, {Pitch = angle(from.pitch, to.pitch), Yaw = angle(from.yaw, to.yaw), Roll = angle(from.roll, to.roll)}, false, {}, true)
    else
        ghost.actor:K2_SetActorLocation(location, false, {}, true)
    end
    if ghost.trail then pcall(drawGhostTrail, ghost, elapsed) end
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
hologramMaterial = function(world, colorOverride)
    local color, colorName = ghostColor()
    if colorOverride then color, colorName = colorOverride, 'estela' end
    local materials = StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
    -- 1) A glass material of the game with colour settings (tinted glass looks like a hologram)
    for _, entry in ipairs(ghostLook.candidates) do
        local hasColor = false
        for _, name in ipairs(entry.vectors) do if name:find('Color', 1, true) then hasColor = true end end
        if hasColor and entry.name:find('Glass', 1, true) then
            local dynamic
            pcall(function() dynamic = materials:CreateDynamicMaterialInstance(world, entry.material, FName('GhostHologram'), 0) end)
            if isValid(dynamic) then
                for _, name in ipairs(entry.vectors) do pcall(function() dynamic:SetVectorParameterValue(FName(name), {R = color.R, G = color.G, B = color.B, A = 1}) end) end
                for _, pair in ipairs({{'Max Opacity', 0.55}, {'Min Opacity', 0.25}, {'Edge Opacity', 0.9}, {'Highlight Opacity', 0.6}}) do
                    pcall(function() dynamic:SetScalarParameterValue(FName(pair[1]), pair[2]) end)
                end
                return dynamic, 'cristal ' .. (entry.name:match('([^%.:/ ]+)$') or '') .. ', color ' .. colorName
            end
        end
    end
    -- 2) The engine's translucent widget material, tinted
    local candidate
    for _, entry in ipairs(ghostLook.candidates) do if entry.name:find('Widget3DPassThrough_Translucent', 1, true) then candidate = entry; break end end
    if not candidate then return nil, 'sin material translúcido' end
    local rendering = StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
    local dynamic, plain
    pcall(function() dynamic = materials:CreateDynamicMaterialInstance(world, candidate.material, FName('GhostHologram'), 0) end)
    if not isValid(dynamic) then return nil, 'no se pudo crear el material' end
    pcall(function() plain = rendering:CreateRenderTarget2D(world, 4, 4, 2, {R = 1, G = 1, B = 1, A = 1}, false) end)
    if not isValid(plain) then pcall(function() plain = rendering:CreateRenderTarget2D(world, 4, 4, 2, {R = 1, G = 1, B = 1, A = 1}, false, false) end) end
    if isValid(plain) then pcall(function() rendering:ClearRenderTarget2D(world, plain, {R = 1, G = 1, B = 1, A = 1}) end); pcall(function() dynamic:SetTextureParameterValue(FName('SlateUI'), plain) end) end
    pcall(function() dynamic:SetScalarParameterValue(FName('OpacityFromTexture'), 0) end)
    pcall(function() dynamic:SetVectorParameterValue(FName('TintColorAndOpacity'), color) end)
    return dynamic, 'widget, color ' .. colorName
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
    local actors, parts = {base}, {static = 0, skeletal = 0}
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
            if visibleOk and visible and isValid(mesh) and not isProxy then
                local location, rotation, scale = component:K2_GetComponentLocation(), component:K2_GetComponentRotation(), component:K2_GetComponentScale()
                local copy = world:SpawnActor(kind == 'static' and actorClass or skeletalClass, {X = location.X, Y = location.Y, Z = location.Z},
                    {Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll})
                if isValid(copy) then
                    local copyComponent = readProperty(copy, kind == 'static' and 'StaticMeshComponent' or 'SkeletalMeshComponent')
                    pcall(function() copyComponent:SetMobility(2) end)
                    if kind == 'static' then pcall(function() copyComponent:SetStaticMesh(mesh) end)
                    else
                        local setOk = pcall(function() copyComponent:SetSkeletalMeshAsset(mesh) end)
                        if not setOk then pcall(function() copyComponent:SetSkeletalMesh(mesh, true) end) end
                    end
                    pcall(function() copyComponent:SetCollisionEnabled(0) end)
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
    return base, actors, string.format('holograma de tu vehículo (%d piezas, %d con esqueleto; material %s)', parts.static + parts.skeletal, parts.skeletal, tostring(materialNote))
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
    local points, heights = ghost.points, {}
    if not needsHeights then
        for index = 1, #points do
            local sum, count = 0, 0
            for other = math.max(1, index - 4), math.min(#points, index + 4) do sum = sum + points[other].z; count = count + 1 end
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
    if TRAIL_ENABLED and race.ghost and isValid(world) and not safeMode.blocked.ghost_look and not safeMode.blocked.ghost_trail then
        local _, trailNote = runGuarded('ghost_look', spawnGhostTrail, race.ghost, pawn, world)
        log('Fantasma: ' .. tostring(trailNote))
    end
    log('Fantasma: ' .. pending.label .. (problem and (' (' .. problem .. ')') or ''))
    startGhostLoop()
end

-- Diagnostics (0.9.29, to find the special turn, the "square" button): every 0.1 s the yes/no and
-- number settings of the vehicle state, the vehicle and its ability or movement parts are compared,
-- and every change goes to state_samples.txt with the race time and lap. Only names and values are read.
local STATE_WATCH_TYPES = {BoolProperty = true, IntProperty = true, ByteProperty = true, EnumProperty = true, FloatProperty = true, DoubleProperty = true}
local STATE_WATCH_LIMIT = 20000
local function watchedPropertyNames(object)
    local names = {}
    pcall(function()
        local class = object:GetClass()
        for _ = 1, 8 do
            if not isValid(class) then break end
            class:ForEachProperty(function(property)
                if STATE_WATCH_TYPES[propertyTypeName(property)] then
                    local nameOk, name = pcall(function() return property:GetFName():ToString() end)
                    if nameOk and name then names[#names + 1] = name end
                end
            end)
            class = class:GetSuperStruct()
        end
    end)
    return names
end
local function startStateWatch(race, pawn)
    local watch = {objects = {}, values = {}, lines = {}, count = 0, nextAt = 0}
    local function add(object, label)
        if isValid(object) then
            local names = watchedPropertyNames(object)
            if #names > 0 then watch.objects[#watch.objects + 1] = {object = object, label = label, names = names} end
        end
    end
    add(readProperty(pawn, 'VehicleState'), 'VehicleState')
    -- 0.9.30: only the vehicle state (read every race for the boost since 0.9.26 without trouble); the
    -- vehicle itself and its ability parts were being read when the game closed twice
    local summary = {}
    for _, entry in ipairs(watch.objects) do summary[#summary + 1] = entry.label .. ' (' .. #entry.names .. ': ' .. table.concat(entry.names, ', ') .. ')' end
    local existing, size = io.open(modFile('state_samples.txt'), 'r'), 0
    if existing then size = existing:seek('end') or 0; existing:close() end
    local vehicle = (race.event and race.event.id or '?'):match('_(BIKE)_') or (race.event and race.event.id or ''):match('_(CAR)_')
        or (race.event and race.event.id or ''):match('_(SKIMMER)_') or (race.event and race.event.id or ''):match('_(PLANE)_') or '?'
    writeFile(modFile('state_samples.txt'), '\n== ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' ' .. tostring(race.label) .. ' | ' .. vehicle .. ' | ' .. table.concat(summary, ', ') ..
        '\ntiempo\tvuelta\tboost\tdato\tantes -> ahora\n', size > 2000000 and 'w' or 'a')   -- one section per race
    race.stateWatch = watch
    -- the whole race counts as the delicate part: if the game closes during it, the next session does not watch
    modState.longGuard = 'state_watch'
    if #guardedOperationStack == 0 then writeFile(OPERATION_IN_PROGRESS_PATH, 'state_watch\n', 'w') end
    log('Diagnóstico de estados: ' .. table.concat(summary, ', ') .. ' -> state_samples.txt')
end
local function sampleStateWatch(race, now, boost)
    local watch = race.stateWatch
    if not watch or now < watch.nextAt or watch.count >= STATE_WATCH_LIMIT then return end
    watch.nextAt = now + 0.1
    local elapsed = now - (race.eventZero or race.startTime or now)
    for _, entry in ipairs(watch.objects) do
        for _, name in ipairs(isValid(entry.object) and entry.names or {}) do
            local ok, value = pcall(function() return entry.object[name] end)
            if ok then
                local text = scalarToText(value)
                -- decimals change all the time: only whether they are zero, positive or negative
                if type(value) == 'number' and math.type and math.type(value) == 'float' then text = value > 1e-4 and '+' or (value < -1e-4 and '-' or '0') end
                local key = entry.label .. '.' .. name
                local before = watch.values[key]
                if before ~= nil and before ~= text then
                    watch.lines[#watch.lines + 1] = string.format('%.2f\t%d\t%s\t%s\t%s -> %s', elapsed, race.lapNumber + 1, boost or '', key, before, text)
                    watch.count = watch.count + 1
                end
                watch.values[key] = text
            end
        end
    end
    if #watch.lines >= 10 then writeFile(modFile('state_samples.txt'), table.concat(watch.lines, '\n') .. '\n'); watch.lines = {} end
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
            race.startDistance = learnedTracks['start|' .. trackKey(race)]
            local savedFinish = learnedTracks['finish|' .. trackKey(race)]
            if savedFinish then
                for index, checkpointDistance in ipairs(race.checkpointDistances) do
                    if math.abs(checkpointDistance - savedFinish) < 1000 then setFinishLine(race, index); log('Meta recordada: checkpoint ' .. index); break end
                end
            end
            writeFile(DIAGNOSTICS_PATH, '', 'w')
            pcall(writeDiagnostics, race, 'salida')
            events = events .. 'START '
            log(string.format('Salida. Sentido %s.', race.direction == 1 and 'de la ruta' or 'inverso'))
            pcall(readPanelLanguage)   -- the language may have changed in the app since the last race
            pcall(readRivals)
            if STATE_WATCH_ENABLED and not safeMode.blocked.state_watch and not race.stateWatch then   -- every race: the file keeps the last one
                local watchOk, watchError = runGuarded('state_watch', startStateWatch, race, pawn)
                if not watchOk then log('Diagnóstico de estados fallido: ' .. tostring(watchError)) end
            end
            -- While the state diagnostics are off, the race counts as the delicate part of the ghost trail:
            -- if the game closes during it, the next session goes without trail
            if not race.stateWatch and race.ghost and race.ghost.trail and not modState.longGuard then
                modState.longGuard = 'ghost_trail'
                if #guardedOperationStack == 0 then writeFile(OPERATION_IN_PROGRESS_PATH, 'ghost_trail\n', 'w') end
            end
            -- The hologram was copied during the intro, when the vehicle may be posed differently (a bike on a
            -- slope ended up upright the whole race): its pieces are put again as your vehicle is at the GO
            if race.ghost and race.ghost.parts then
                local snapOk, snapError = pcall(function()
                    local base = race.ghost.actor
                    local where, facing = pawn:K2_GetActorLocation(), pawn:K2_GetActorRotation()
                    base:K2_SetActorLocationAndRotation({X = where.X, Y = where.Y, Z = where.Z}, {Pitch = facing.Pitch, Yaw = facing.Yaw, Roll = facing.Roll}, false, {}, true)
                    for _, part in ipairs(race.ghost.parts) do
                        if isValid(part.copy) and isValid(part.source) then
                            local location, rotation = part.source:K2_GetComponentLocation(), part.source:K2_GetComponentRotation()
                            part.copy:K2_SetActorLocationAndRotation({X = location.X, Y = location.Y, Z = location.Z},
                                {Pitch = rotation.Pitch, Yaw = rotation.Yaw, Roll = rotation.Roll}, false, {}, true)
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
        race.ghostReportAt = now + 10
        pcall(function()
            local where = race.ghost.actor:K2_GetActorLocation()
            log(string.format('Fantasma: a %.0f s, a %.0f m de ti', now - race.startTime,
                math.sqrt((where.X - position.X) ^ 2 + (where.Y - position.Y) ^ 2 + (where.Z - position.Z) ^ 2) / 100))
        end)
    end
    -- Points of this race for its ghost, every 0.1 s from the start
    if race.eventTime and race.eventTime > 0.05 and not race.eventEnded then
        local zero = now - race.eventTime   -- the moment of the GO in the game clock (the lowest is the freshest reading)
        if not race.eventZero or zero < race.eventZero then race.eventZero = zero end
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
    if race.stateWatch then pcall(sampleStateWatch, race, now, boostOk and boost or '') end
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
                    if ghostTime then race.liveDifference = (now - race.liveLap.startTime) - ghostTime end
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
        local runningTime = running and math.max(0, now - liveLap.startTime)
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
-- Diagnostics (once per session): names and types of the track and planet properties, without
-- reading their values except checked texts. They go to log.txt.
local planetDiagnosticsDone, planetNameDiagnosticsDone, loadedPlanetsLogged = false, false, false
-- Planet codes in the event names and the game's internal codename of each planet
local PLANET_CODENAMES = {DAL = 'Dalmatian', MAS = 'Mastiff', COR = 'Corgi', SPA = 'Spaniel', HSK = 'Husky', WHP = 'Whippet', BGL = 'Beagle'}
-- Diagnostics (once): every planet the game has loaded, with its visible name
local function logLoadedPlanets()
    loadedPlanetsLogged = true
    local planets = {}
    for _, planetDefinition in ipairs(FindAllOf('PlanetDef') or {}) do
        if isLiveObject(planetDefinition) then
            local shortName = (fullName(planetDefinition):match('%.([%w_]+)$') or '?')
            planets[#planets + 1] = shortName .. ' = "' .. readAssetText(planetDefinition, {'PlayerFacingName'}) .. '"'
            if #planets >= 20 then break end
        end
    end
    log('Diagnóstico planeta · cargados: ' .. (#planets > 0 and table.concat(planets, ', ') or 'ninguno'))
end
local function propertiesMatching(object, pattern)
    local matches = {}
    pcall(function()
        local class = object:GetClass()
        for _ = 1, 10 do
            if not isValid(class) then break end
            class:ForEachProperty(function(property)
                local nameOk, propertyName = pcall(function() return property:GetFName():ToString() end)
                if nameOk and propertyName:lower():find(pattern) then matches[#matches + 1] = propertyName .. ' (' .. propertyTypeName(property) .. ')' end
                if #matches > 30 then return true end
            end)
            class = class:GetSuperStruct()
        end
    end)
    return matches
end
local categoryDiagnosticsCount = 0
local CATEGORY_PROPERTY_TYPES = {ByteProperty = true, EnumProperty = true, IntProperty = true, BoolProperty = true, NameProperty = true, ObjectProperty = true}
local function logCategoryDiagnostics(eventDefinition)
    if categoryDiagnosticsCount >= 8 then return end
    categoryDiagnosticsCount = categoryDiagnosticsCount + 1
    local found = {}
    for _, match in ipairs(propertiesMatching(eventDefinition, '')) do
        local propertyName, propertyType = match:match('^(%S+) %((%S+)%)$')
        local lowerName = propertyName and propertyName:lower() or ''
        if propertyType and CATEGORY_PROPERTY_TYPES[propertyType] and (lowerName:find('categ') or lowerName:find('type') or lowerName:find('mode')
            or lowerName:find('tag') or lowerName:find('filter') or lowerName:find('kind') or lowerName:find('group')) then
            local readOk, value = pcall(function() return eventDefinition[propertyName] end)
            local text = '?'
            if readOk then
                if type(value) == 'number' or type(value) == 'boolean' then text = tostring(value)
                elseif propertyType == 'NameProperty' then
                    local nameOk, nameText = pcall(function() return value:ToString() end); text = nameOk and nameText or '?'
                elseif propertyType == 'ObjectProperty' then text = isValid(value) and (fullName(value):gsub('^%S+ ', '')) or 'ninguno' end
            end
            found[#found + 1] = propertyName .. ' (' .. propertyType .. ') = ' .. tostring(text)
        end
    end
    log('Diagnóstico categoría · ' .. (fullName(eventDefinition):gsub('^%S+ ', '')) .. ': ' .. (#found > 0 and table.concat(found, ', ') or 'nada parecido'))
end
local function logPlanetDiagnostics(eventDefinition, trackDefinition)
    if planetDiagnosticsDone then return end
    planetDiagnosticsDone = true
    log('Diagnóstico planeta · evento ' .. fullName(eventDefinition):gsub('^%S+ ', '') .. ': ' .. table.concat(propertiesMatching(eventDefinition, 'planet'), ', '))
    if isLiveObject(trackDefinition) then
        log('Diagnóstico planeta · pista: ' .. table.concat(propertiesMatching(trackDefinition, 'planet'), ', '))
        for _, match in ipairs(propertiesMatching(trackDefinition, 'planet')) do
            local propertyName, propertyType = match:match('^(%S+) %((%S+)%)$')
            if propertyType == 'ObjectProperty' then
                local readOk, planetDefinition = pcall(function() return trackDefinition[propertyName] end)
                if readOk and isLiveObject(planetDefinition) then
                    local texts = {}
                    for _, planetMatch in ipairs(propertiesMatching(planetDefinition, '')) do
                        local textName, textType = planetMatch:match('^(%S+) %((%S+)%)$')
                        if textType and TEXT_PROPERTY_TYPES[textType] then
                            texts[#texts + 1] = textName .. ' (' .. textType .. ') = "' .. readAssetText(planetDefinition, {textName}) .. '"'
                        end
                    end
                    log('Diagnóstico planeta · ' .. fullName(planetDefinition):gsub('^%S+ ', '') .. ': ' .. table.concat(texts, ', '))
                end
            end
        end
    end
end
-- Name, planet, planet codename and category of an event definition (remembered per event)
local function readEventNames(eventDefinition)
    local key = fullName(eventDefinition)
    if eventNameCache[key] then local cached = eventNameCache[key]; return cached[1], cached[2], cached[3], cached[4] end
    local eventName = readAssetText(eventDefinition, {'PlayerFacingName'})
    local planet = ''
    local trackOk, trackDefinition = pcall(function() return eventDefinition.TrackDef end)
    if trackOk then pcall(logPlanetDiagnostics, eventDefinition, trackDefinition) end
    pcall(logCategoryDiagnostics, eventDefinition)
    -- The track keeps its planet as a path (SoftObject), which is not read: the codename comes from the
    -- path of the track itself (.../Planets/Dalmatian/...) and the name from the PlanetDef the game has loaded.
    local planetCodename = trackOk and isLiveObject(trackDefinition) and fullName(trackDefinition):match('/Planets/([%w_]+)/') or ''
    if planetCodename == '' then   -- podracing tracks are not under a planet: it comes from the event code (EVT_ARC_TT_PLANE_BGL_...)
        local planetCode = (fullName(eventDefinition):match('([%w_]+)$') or ''):match('^EVT_ARC_%u+_%u+_(%u%u%u)_')
        planetCodename = PLANET_CODENAMES[planetCode or ''] or ''
    end
    if not loadedPlanetsLogged then pcall(logLoadedPlanets) end
    if planetCodename ~= '' then
        local findOk, planetDefinition = pcall(StaticFindObject, '/Game/Griffin/Gameplay/Config/Planets/PLA_' .. planetCodename .. '.PLA_' .. planetCodename)
        if findOk and isLiveObject(planetDefinition) then
            planet = readAssetText(planetDefinition, {'PlayerFacingName', 'DisplayName', 'PlanetName', 'Title'})
            if not planetNameDiagnosticsDone then
                planetNameDiagnosticsDone = true
                local texts = {}
                for _, match in ipairs(propertiesMatching(planetDefinition, '')) do
                    local textName, textType = match:match('^(%S+) %((%S+)%)$')
                    if textType and TEXT_PROPERTY_TYPES[textType] then texts[#texts + 1] = textName .. ' = "' .. readAssetText(planetDefinition, {textName}) .. '"' end
                end
                log('Diagnóstico planeta · PLA_' .. planetCodename .. ': ' .. (#texts > 0 and table.concat(texts, ', ') or 'sin textos'))
            end
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
-- Record search with Ctrl+Shift+K, registered in UE4SS so it also works in the menus
if type(RegisterKeyBind) == 'function' and Key and Key.K and ModifierKey then
    local ok, err = pcall(function()
        RegisterKeyBind(Key.K, {ModifierKey.CONTROL, ModifierKey.SHIFT}, function()
            local runSearch = function()
                log('Buscando récords en el juego (puede tardar unos segundos)...')
                local searchOk, searchError = runGuarded('record_search', searchGameForRecords)
                if not searchOk then log('Búsqueda de récords fallida: ' .. tostring(searchError)) end
            end
            if type(ExecuteInGameThread) == 'function' then ExecuteInGameThread(runSearch) else runSearch() end
        end)
    end)
    if not ok then log('No se pudo registrar Ctrl+Shift+K: ' .. tostring(err)) end
end

log('READY v' .. VERSION .. '. Ctrl+F9 pausa/reanuda la grabación, Ctrl+F10 muestra/oculta el panel, Ctrl+Shift+K busca tus récords. Archivos en la carpeta del mod.')
