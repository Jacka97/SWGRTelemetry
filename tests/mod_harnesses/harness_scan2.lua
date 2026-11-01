-- Simulador de UE4SS para probar el mod fuera del juego.
-- Circuito circular de radio R, checkpoints a 1/3 y 2/3, coche a velocidad constante
-- (más lento en el sector 2 de la vuelta 2), salida desde parrilla detrás de la línea.
local MODE = ... or 'pre'   -- 'pre' (parrilla detrás de la línea) | 'standing' | 'reverse'
local R = 20000
local L = 2 * math.pi * R
local T = 0
local function obj(t, nm, ad)
    t.IsValid = function() return true end
    t.GetFullName = function() return nm end
    t.GetAddress = function() return ad end
    return t
end
local world = obj({}, 'World /Game/Maps/Jakku/L_Jakku_Main.L_Jakku_Main', 1)
local function tarray(items)
    local a = {}
    a.type = function() return 'TArray' end
    a.ForEach = function(self, fn) for i, v in ipairs(items) do fn(i, {get = function() return v end}) end end
    return setmetatable(a, {__len = function() return #items end})
end
local function onCircle(ang) return {X = R * math.cos(ang), Y = R * math.sin(ang), Z = 100 * math.sin(3 * ang)} end
local spline = obj({}, 'SplineComponent /Game/Maps/Jakku/L_Jakku_Main.L_Jakku_Main:PersistentLevel.Route.Spline', 2)
spline.GetSplineLength = function() return L end
spline.GetWorldLocationAtDistanceAlongSpline = function(_, d) return onCircle(d / R) end
local cps = {}
for _, f in ipairs({1/3, 2/3, 0.97}) do
    local c = obj({}, 'Checkpoint', 10)
    c.K2_GetActorLocation = function() return onCircle(2 * math.pi * f) end
    cps[#cps + 1] = c
end
local route = obj({mMainRouteSpline = spline, Checkpoints = tarray(cps)}, 'RaceRoute /Game/Maps/Jakku/L_Jakku_Main.L_Jakku_Main:PersistentLevel.BP_Route_C_1', 3)
local track = obj({}, 'TrackDef', 4); track.GetFName = function() return {ToString = function() return 'TD_Jakku_Canyon_FWD' end} end
local ldb = obj({}, 'LeaderboardDef /Game/Griffin/Gameplay/Arcade/Leaderboards/TimeTrial/LDB_ARC_TT_BIKE_DAL_A_SHORT_01.LDB_ARC_TT_BIKE_DAL_A_SHORT_01', 40)
ldb.GetFName = function() return {ToString = function() return 'LDB_ARC_TT_BIKE_DAL_A_SHORT_01' end} end
local vmObj = obj({track = track, LeaderboardDef = ldb, ModeName = {ToString = function() return 'Contrarreloj' end}, NumLaps = 3, CurrentEventTime = 0, CurrentTargetTime = 88.5, CurrentTargetTimeRank = 1,
    CurrentTargetPlayerName = {ToString = function() return 'Kestar Bool' end}, bIsSuccess = false}, 'VM', 5)
local gs = obj({RaceRoute = route, RaceEventViewModel = vmObj, LapCount = 3}, 'RacingGameState', 6)
gs.GetWorld = function() return world end
local ps = obj({}, 'PlayerState', 7)
local comp = obj({PreviousLapTime = 0.0, ChosenVehicleType = 2, bHasFinishedEvent = false, EventFinishTime = -1}, 'PlayerRaceEventComponent', 8)
comp.GetOwner = function() return ps end
-- Coche
local ang = (MODE == 'standing') and (0.97*2*math.pi+0.01) or (0.85*2*math.pi)
local dirSign = (MODE == 'reverse') and -1 or 1
if MODE == 'reverse' then ang = -0.85*2*math.pi end
local speed = 0     -- cm/s
local pawn = obj({}, 'Pawn', 9)
pawn.K2_GetActorLocation = function() return onCircle(ang) end
pawn.GetVelocity = function()
    return {X = -math.sin(ang) * speed * dirSign, Y = math.cos(ang) * speed * dirSign, Z = 0}
end
pawn.GetActorForwardVector = function() return {X = -math.sin(ang) * dirSign, Y = math.cos(ang) * dirSign, Z = 0} end
local pc = obj({Pawn = pawn, PlayerState = ps}, 'PlayerController', 11)
pc.IsLocalPlayerController = function() return true end
pc.GetWorld = function() return world end
pc.IsInputKeyDown = function(_, k) return SCAN_NOW == true and (k.KeyName == 'F11' or k.KeyName == 'LeftControl') end
local function fprop(nm, ty, extra)
    local p = extra or {}
    p.GetFName = function() return {ToString = function() return nm end} end
    p.GetClass = function() return {GetFName = function() return {ToString = function() return ty end} end} end
    return p
end
local entryStruct = {ForEachProperty = function(_, fn) fn(fprop('BestTime', 'FloatProperty')); fn(fprop('EventId', 'NameProperty')) end}
local recStruct = {ForEachProperty = function(_, fn) fn(fprop('Seconds', 'DoubleProperty')); fn(fprop('Holder', 'StrProperty')) end}
local entries = tarray({{BestTime = 82.159, EventId = {ToString = function() return 'LDB_ARC_TT_BIKE_DAL_A_SHORT_01' end}}, {BestTime = 95.2, EventId = {ToString = function() return 'LDB_X' end}}})
entries.type = function() return 'TArray' end
local fakeSave = obj({}, 'GfnArcadeSaveGame /Engine/Transient.GfnArcadeSaveGame_0', 50)
local saveData = {BestTimes = 81.5, Records = entries, Last = {Seconds = 82.3, Holder = 'boom'}}
setmetatable(fakeSave, {__index = function(_, k)
    if k == 'PlayerName' then error('CRASH: se leyó un texto de un objeto vivo') end
    return saveData[k] end})
fakeSave.GetClass = function() return obj({ForEachProperty = function(_, fn)
    fn(fprop('BestTimes', 'FloatProperty'))
    fn(fprop('PlayerName', 'StrProperty'))
    fn(fprop('Records', 'ArrayProperty', {GetInner = function() return fprop('Inner', 'StructProperty', {GetStruct = function() return entryStruct end}) end}))
    fn(fprop('Last', 'StructProperty', {GetStruct = function() return recStruct end}))
    fn(fprop('OnChanged', 'MulticastDelegateProperty'))
  end, GetSuperStruct = function() return nil end}, 'Class /Script/Griffin.GfnArcadeSaveGame', 51) end
local trash = obj({}, 'GfnProfileSave /Engine/Transient.TRASH_GfnProfileSave_3', 52)
trash.GetClass = function() error('CRASH: objeto basura') end
ForEachUObject = function(fn) for _, o in ipairs({ldb, fakeSave, trash, pc, comp, gs}) do fn(o, 0, 0) end end
KEYBINDS = {}
Key = {K = 'K'}; ModifierKey = {CONTROL = 'CTRL', SHIFT = 'SHIFT'}
RegisterKeyBind = function(k, mods, fn) KEYBINDS[#KEYBINDS + 1] = fn end
ExecuteInGameThread = function(fn) fn() end
-- Globales de UE4SS
local registry = {PlayerController = {pc}, RacingGameState = {gs}, PlayerRaceEventComponent = {comp}, ArcadeEntryVM = {}}
local function mkvm(id, entries, att, nm)
    local d = obj({}, 'LeaderboardDef /Game/x/' .. id .. '.' .. id, 60)
    d.GetFName = function() return {ToString = function() return id end} end
    local pd = obj({PlayerFacingName = {ToString = function() return 'Lantaana' end}}, 'PlanetDef /Game/PLA_Dalmatian', 61)
    local td = obj({Planet = pd}, 'TrackDef /Game/T', 62)
    local ed = obj({PlayerFacingName = {ToString = function() return nm end}, TrackDef = td}, 'ArcadeEventDef /Game/E_' .. id, 63)
    return obj({LeaderboardDef = d, EventDef = ed, LeaderboardEntries = tarray(entries), NumberOfAttempts = att}, 'ArcadeEntryVM /Engine/Transient.X', 64)
end
registry.ArcadeEntryVM = {
  mkvm('LDB_ARC_TT_BIKE_DAL_A_SHORT_01', {{bIsLocalPlayer = false, bIsAuthoredTime = true, RawStatValue = 82}, {bIsLocalPlayer = true, bIsAuthoredTime = false, RawStatValue = 80.375}}, 30, 'As de motos speeder'),
  mkvm('LDB_ARC_TT_BIKE_DAL_A_SHORT_01', {{bIsLocalPlayer = true, bIsAuthoredTime = false, RawStatValue = 80.375}}, 30, 'As de motos speeder'),
  mkvm('LDB_ARC_TT_CAR_MAS_A_SHORT_02', {{bIsLocalPlayer = false, RawStatValue = 70}, {bIsLocalPlayer = true, RawStatValue = 74.54}}, 16, 'Prueba de deslizador'),
  mkvm('LDB_ARC_PRE_X', {{bIsLocalPlayer = false, RawStatValue = 70}}, 0, 'Sin tiempo'),
}
FindAllOf = function(c) return registry[c] end
FName = function(s) return s end
local statics = obj({}, 'GameplayStatics', 12)
statics.GetTimeSeconds = function() return T end
statics.GetViewportSize = function() return {X = 1920, Y = 1080} end
statics.GetViewportScale = function() return 1 end
StaticFindObject = function() return statics end
FText = function(s) return s end
HUD_TEXTS = {}
local wid = 100
local function widget()
    wid = wid + 1
    local w = obj({Font = {Size = 0}}, 'Widget', wid)
    local function noop() end
    for _, m in ipairs({'SetPadding','SetBrushColor','SetContent','SetRenderTransformPivot','SetRenderScale','SetJustification','AddToViewport','RemoveFromParent'}) do w[m] = noop end
    w.SetVisibility = function(_, v) w.vis = v end
    w.IsInViewport = function() return true end
    w.AddChildToCanvas = function() return {SetSize = noop, SetPosition = noop} end
    w.SetText = function(_, s) w.txt = s end
    w.SetColorAndOpacity = function(_, c) local k = c.SpecifiedColor; w.col = (k.B > 0.9 and k.G < 0.6) and 'morado' or (k.G > 0.8 and k.R < 0.5) and 'verde' or (k.R > 0.95 and k.B < 0.45) and (k.G > 0.6 and 'ambar' or 'rojo') or '' end
    HUD_TEXTS[#HUD_TEXTS + 1] = w
    return w
end
StaticConstructObject = function() return widget() end
function DUMP_HUD(label)
    local texts = {}
    for _, w in ipairs(HUD_TEXTS) do if w.txt ~= nil then texts[#texts + 1] = w end end
    print('--- ' .. label)
    local n = #texts - (#texts % 3)
    for i = math.max(1, #texts - 26), #texts, 3 do
        local a, b, c = texts[i], texts[i + 1], texts[i + 2]
        if a and b and c then
            print(string.format('   %-10s %10s %-7s %9s %s', a.txt, b.txt, b.col ~= '' and '['..b.col..']' or '', c.txt, c.col ~= '' and '['..c.col..']' or ''))
        end
    end
end
local loop
LoopInGameThreadWithDelay = function(_, fn) loop = fn end
local clock = 0
os.clock = function() return clock end
local realExec = os.execute
os.execute = function(cmd)
    local path = cmd:match('mkdir "(.-)"'):gsub('\\', '/')
    return realExec('mkdir -p "' .. path .. '"')
end
dofile(MOD_PATH)
local crashed = false
-- Simulación: 2 s parado, luego 3 vueltas. Cada vuelta ~ 30 s.
local dt = 0.02
local laps = 0
local lineT = nil
local lapStartT = nil
local pendingOfficial = nil
local function sectorSpeed(frac, lap)
    local base = L / 30 * (SPEEDF or 1)
    if lap == 2 and frac > 1/3 and frac < 2/3 then return base * 0.8 end
    if lap == 3 and frac < 1/3 then return base * 1.1 end
    return base
end
local prevProg = nil
for step = 1, 200000 do
    T = T + dt; clock = clock + dt
    if T > 2 then
        local prog = ((ang * dirSign) % (2 * math.pi)) / (2 * math.pi)
        speed = sectorSpeed(prog, laps + 1)
        if laps >= 3 then speed = speed * 0.45 end   -- piloto automático tras la última vuelta
        ang = ang + dirSign * speed * dt / R
        if laps == 1 and not crashed and prog > 0.55 and prog < 0.6 then
            crashed = true; ang = ang - dirSign * 0.2; T = T + 3; clock = clock + 3   -- choque: 3 s parado y 30 m atrás
        end
        local newProg = ((ang * dirSign) % (2 * math.pi)) / (2 * math.pi)
        if prevProg and prevProg < 0.97 and newProg >= 0.97 then
            -- cruce real de la línea
            if lapStartT then
                laps = laps + 1
                pendingOfficial = {at = T + 0.1, v = T - lapStartT}  -- el juego publica 0.1 s después
            end
            lapStartT = T
        end
        if MODE == 'standing' and not lapStartT then lapStartT = 2 end
        prevProg = newProg
    end
    if pendingOfficial and T >= pendingOfficial.at then
        comp.PreviousLapTime = pendingOfficial.v
        SUMLAPS = (SUMLAPS or 0) + pendingOfficial.v
        if laps >= 3 then comp.bHasFinishedEvent = true; comp.EventFinishTime = SUMLAPS; vmObj.bIsSuccess = SUMLAPS < 88.5 end
        print(string.format('   [sim] oficial publicado %.3f', pendingOfficial.v))
        pendingOfficial = nil
    end
    if FIRSTLINE == nil and lapStartT then FIRSTLINE = lapStartT end
    if FIRSTLINE and not comp.bHasFinishedEvent then vmObj.CurrentEventTime = T - FIRSTLINE end
    SCAN_NOW = (T > 30 and T < 30.05)
    if SCAN_NOW and not SCANNED then SCANNED = true; for _, f in ipairs(KEYBINDS) do f() end end
    loop()
    for _, snap in ipairs(SNAPS or {}) do
        if not snap.done and T >= snap.t then snap.done = true; DUMP_HUD(snap.label .. string.format(' (t=%.1f s)', T)) end
    end
    if laps >= 3 and not pendingOfficial and T > lapStartT + 16 then break end
end
_G.SWGRTelemetry.stop()
