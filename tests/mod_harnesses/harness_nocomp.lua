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
for _, f in ipairs({1/3, 2/3}) do
    local c = obj({}, 'Checkpoint', 10)
    c.K2_GetActorLocation = function() return onCircle(2 * math.pi * f) end
    cps[#cps + 1] = c
end
local route = obj({mMainRouteSpline = spline, Checkpoints = tarray(cps)}, 'RaceRoute /Game/Maps/Jakku/L_Jakku_Main.L_Jakku_Main:PersistentLevel.BP_Route_C_1', 3)
local track = obj({}, 'TrackDef', 4); track.GetFName = function() return {ToString = function() return 'TD_Jakku_Canyon_FWD' end} end
local ldbArc = obj({}, 'LeaderboardDef LDB_ARC_TT_BIKE_JAK_TEST', 41)
ldbArc.GetFName = function() return {ToString = function() return 'LDB_ARC_TT_BIKE_JAK_TEST' end} end
local gs = obj({RaceRoute = route, RaceEventViewModel = obj({track = track, LeaderboardDef = ldbArc}, 'VM', 5)}, 'RacingGameState', 6)
gs.GetWorld = function() return world end
local ps = obj({}, 'PlayerState', 7)
local comp = obj({PreviousLapTime = 0.0, ChosenVehicleType = 2}, 'PlayerRaceEventComponent', 8)
comp.GetOwner = function() return ps end
-- Coche
local ang = (MODE == 'standing') and 0.05 or -0.02
local dirSign = (MODE == 'reverse') and -1 or 1
if MODE == 'reverse' then ang = 0.02 end
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
pc.IsInputKeyDown = function() return false end
-- Globales de UE4SS
local registry = {PlayerController = {pc}, RacingGameState = {gs}, PlayerRaceEventComponent = {}}
FindAllOf = function(c) return registry[c] end
FName = function(s) return s end
local statics = obj({}, 'GameplayStatics', 12)
statics.GetTimeSeconds = function() return T end
StaticFindObject = function() return statics end
local loop
LoopInGameThreadWithDelay = function(_, fn) loop = fn end
local clock = 0
os.clock = function() return clock end
dofile(MOD_PATH)
-- Simulación: 2 s parado, luego 3 vueltas. Cada vuelta ~ 30 s.
local dt = 0.02
local laps = 0
local lineT = nil
local lapStartT = nil
local pendingOfficial = nil
local function sectorSpeed(frac, lap)
    local base = L / 30
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
        ang = ang + dirSign * speed * dt / R
        local newProg = ((ang * dirSign) % (2 * math.pi)) / (2 * math.pi)
        if prevProg and prevProg > 0.9 and newProg < 0.1 then
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
        print(string.format('   [sim] oficial publicado %.3f', pendingOfficial.v))
        pendingOfficial = nil
    end
    loop()
    if laps >= 3 and not pendingOfficial and T > lapStartT + 5 then break end
end
_G.SWGRTelemetry.stop()
