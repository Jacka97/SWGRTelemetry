# SWGR Telemetry

Mod de UE4SS y app local para el Arcade de STAR WARS Galactic Racer. Graba tu telemetría en cada evento, te muestra un panel de tiempos en carrera, pone un fantasma con tu mejor carrera (o la de un amigo) y te deja analizar cada vuelta en una app en tu PC.

Herramienta no oficial hecha por fans, sin relación con Lucasfilm, Disney ni los creadores del juego.

## Qué hace

- Panel en carrera: tiempo de vuelta, sectores con su diferencia, diferencia en directo con tu mejor vuelta, récord y objetivo nº1.
- Fantasma en pista: un holograma de tu vehículo recorre tu mejor carrera, la de tu amigo más rápido o la del amigo que elijas.
- App de análisis: mapa con tu trazada y velocidad, comparación A contra B vuelta a vuelta, repetición, vuelta ideal, gráficas y progreso.
- Archivos de piloto: exporta tus tiempos y fantasmas y compárate con tus amigos.
- Funciona solo en los eventos de Arcade y todo se queda en tu PC: la app no usa internet.

## Instalación

1. Instala UE4SS Galactic Racer Edition en el juego.
2. Descarga el zip de la última versión en [Releases](../../releases/latest).
3. Descomprímelo en `STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\`. Debe quedar `Mods\SWGRTelemetry\Scripts\main.lua` y `Mods\SWGRTelemetry\enabled.txt`.
4. Entra en un evento de Arcade: el mod empieza a grabar solo. Para ver tu telemetría abre `Mods\SWGRTelemetry\GalacticRacerTelemetry.exe`.

Las guías completas van dentro del zip, en la carpeta `docs`.

## Importante

El mod solo funciona en los eventos de Arcade: en la historia y en el multijugador no graba ni muestra nada. UE4SS se carga con el juego en todos los modos, así que antes de jugar al multijugador se recomienda quitar o renombrar `dwmapi.dll` en la carpeta `Win64` del juego (vuelve a dejarlo como estaba para usar el mod).

---

# SWGR Telemetry (English)

A UE4SS mod and local app for the Arcade of STAR WARS Galactic Racer. It records your telemetry in every event, shows a timing panel in the race, puts a ghost of your best race (or a friend's) on the track and lets you analyse every lap in an app on your PC.

An unofficial fan-made tool, not related to Lucasfilm, Disney or the makers of the game.

## What it does

- In-race panel: lap time, sectors with their difference, live difference with your best lap, record and #1 target.
- In-track ghost: a hologram of your vehicle runs your best race, your fastest friend's or the one of the friend you pick.
- Analysis app: map with your racing line and speed, A versus B comparison lap by lap, replay, ideal lap, charts and progress.
- Pilot files: export your times and ghosts and compare yourself with your friends.
- It only works in Arcade events and everything stays on your PC: the app does not use the internet.

## Install

1. Install UE4SS Galactic Racer Edition in the game.
2. Download the zip of the latest version from [Releases](../../releases/latest).
3. Unzip it into `STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\`. You should end up with `Mods\SWGRTelemetry\Scripts\main.lua` and `Mods\SWGRTelemetry\enabled.txt`.
4. Enter an Arcade event: the mod starts recording by itself. To see your telemetry open `Mods\SWGRTelemetry\GalacticRacerTelemetry.exe`.

The full guides are inside the zip, in the `docs` folder.

## Important

The mod only works in Arcade events: in the story and in multiplayer it records and shows nothing. UE4SS is loaded with the game in every mode, so before playing multiplayer we recommend removing or renaming `dwmapi.dll` in the game's `Win64` folder (restore it to use the mod).
