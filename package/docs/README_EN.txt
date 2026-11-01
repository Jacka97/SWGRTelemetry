SWGR Telemetry v0.9.31 - for OFFLINE practice
(The mod and the app now share the same version number; both will become 1.0 together.)

Installation
  Copy the SWGRTelemetry folder into:
  STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\
  You should end up with ue4ss\Mods\SWGRTelemetry\Scripts\main.lua and ue4ss\Mods\SWGRTelemetry\enabled.txt
  Requires UE4SS Galactic Racer Edition.

Files renamed in 0.9.18
  The files in the mod folder now have English names (registro.txt -> log.txt,
  records_auto.txt -> game_records.txt, circuitos -> tracks, amigos -> friends, fuentes -> fonts...).
  Nothing to do: the mod and the app rename them by themselves the first time, without losing data.
  The app is now called GalacticRacerTelemetry.exe: if you had a shortcut to the old one,
  create it again.

Usage
  Enter an Arcade event: the mod detects the track and starts recording on its own.
  Ctrl+F9: pause / resume recording.
  Ctrl+F10: show / hide the timing panel.
  Ctrl+Shift+K: search the game for where it keeps your records (creates record_search.txt;
                record_search_progress.txt says how far it got, in case something fails).
                Also works in the menus. It can freeze the game for a few seconds.

Safe mode
  If the game closes suddenly while the mod is doing something delicate (creating the panel,
  reading your records, the Ctrl+Shift+K search or hooking into the race), that part is turned
  off the next time you open the game and everything else keeps working. It is noted in
  logs\safe_mode.txt and the app shows it at the top. If errors keep coming non-stop (for instance
  after a game patch), the mod stops recording for that session instead of insisting.
  To try again: the app's "Try again" button, or delete safe_mode.txt.
  Installing a new version of the mod also tries everything again.
  logs\operation_in_progress.txt: the mod creates it only while it is doing one of those parts; leave it alone.
  logs\log.txt: the mod's messages from the last session, written as they happen (useful to know
  what was going on if the game closes suddenly).

Timing panel (text only, no racing lines or aids)
  It follows the app's language: English when the app is in English or Aurebesh, Spanish
  otherwise (the change shows when the next race starts). Below, the English labels.
  Current lap and time, each sector with its difference against your best sector,
  and below your last lap, your best lap and the ideal lap (sum of your best sectors).
  TOTAL: total time of the event, which is what counts in Arcade.
  TARGET: the fastest of your friend who beats you, your record and the game's #1 (the row carries
  the name: PEPE, RECORD or #1) and, on the right, how much you need per lap over the remaining
  laps to reach it (green if your best lap is enough). Your friends' times are passed to the mod
  by the app (rivals.txt) when it reads their pilot files.
  FORECAST: the total you would finish with at your pace and its gap to the target (not on
  single-lap stages nor in Precision events, where the game takes time off).
  TOP: top and minimum speed of the lap (green if you match those of your best lap).
  IDEAL: on the right, during the lap, what you are leaving against your best sectors.
  Colours: purple = new best sector · green = better than the previous lap ·
           amber = worse than the previous lap · grey = time of the previous lap.
  DELTA: how far ahead (green) or behind (red) your reference lap you are at every moment.
  The reference is your fastest clean lap recorded with this version (ghosts.txt);
  the first time in an event it shows from the second lap. Lap 1 has its own reference
  (see Start): on a new circuit, its DELTA shows from the second race.
  Start: in events with several laps you start slower, so the S1 of lap 1 is only compared
  with other start S1s, and the time of lap 1 with other laps 1 (its DELTA too). The rest of the
  sectors of lap 1 count like those of any lap.
  Bars: one per sector, in the colour of how it went (purple, green, amber; grey if not yet).
  When the event ends, the title tells you if you beat your record or the #1.
  When a lap ends it stays for 5 seconds with the full lap.
  When the event ends it shows END with your last lap and your total against the target.
  The first time on a circuit it shows up when you complete the first lap (when the finish
  line is located); after that it remembers it and shows from the start.
  config\timing_panel.ini (created by itself): style (style: current, sith or compact), position (x, y),
  size (scale), background opacity (opacity), which rows are shown and whether each sector is
  compared with your best sector or with the previous lap (compare_with: best or previous).

Files it creates
  data\event_records.txt            per Arcade event: best total, best lap, attempts and target
  data\best_times.txt               your best laps and sectors per track and vehicle
  data\learned_tracks.txt           finish line and number of laps of each circuit
  data\ghosts.txt                   your reference lap of each event, for the live difference
  data\game_records.txt             your game records, read from the Arcade menu
  logs\diagnostics.txt              internal data of the last race (to improve the mod)
  config\timing_panel.ini           timing panel settings
  race_ghosts\                      your race ghost of each event and your fastest friend's
  tracks\<track>\                   one folder per circuit and direction, with:
    route.csv                       circuit geometry and checkpoints (for the viewer)
    history.txt                     all your laps from every session
    <date>.csv                      one row every ~20 ms: time, lap, progress,
                                    position, speed (km/h), heading, events
    <date>_summary.txt              laps of the session with sectors and differences, and the
                                    event result against the target

Arcade only
  The mod only records and shows the panel in Arcade: each event has its own preset vehicle and
  build, so times are comparable. Records are kept per event (its leaderboard in the game).
  In the campaign, online and other modes it does nothing.
  Quick restarts: if you restart before 20 s of racing, only the attempt is counted (no files).

In-track ghost
  A hologram of your vehicle runs the fastest whole race of the event: yours or your fastest
  friend's (the app takes it from their pilot file). It is for comparing racing lines while you
  race; it has no collision and does not count as a racer.
  Your ghost is saved at the end of the event when you improve your total (race_ghosts\<event>.txt).
  The first time in an event there is no ghost: it shows from the second race.
  Colour: in the app, ⚙ menu > In-track ghost colour (it applies from the next race).
  If the hologram cannot be made, a sphere shows instead.

Notes
  - Lap times are the game's official ones. The finish line is located by itself: it is the
    checkpoint crossed when the game publishes the lap. Sectors go from checkpoint to
    checkpoint and add up exactly to the official time.
  - Sectors are the game's official ones (its own sector timer) when they match the circuit's
    checkpoints; otherwise the ones detected by the mod are used.
  - Checkpoints are detected by your progress along the route (their time matches the official
    one) and, if you take an alternative line far from the centre, by crossing their gate.
  - If you crash or go backwards, the lap is marked as an "incident" and the time lost shows
    in the sector where it happened.
  - The first race on a new circuit is saved in the mod folder and the app moves it by itself
    to tracks\<circuit>\ (the mod opens no window, so the game does not leave full screen);
    from then on the mod records straight into that folder.
  - The stretch from the grid to the first time you cross the finish line does not count as a lap.
  - The panel is an in-race aid: use it offline only.
  - Before playing online or uploading times to the leaderboard: turn UE4SS off (remove dwmapi.dll).
  - Uninstall: delete the SWGRTelemetry folder, or just enabled.txt to turn it off.
