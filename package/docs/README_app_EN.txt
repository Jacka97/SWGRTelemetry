Galactic Racer Telemetry 0.9.31 - local app for the SWGR Telemetry mod

Installation
  Copy GalacticRacerTelemetry.exe into the mod folder:
  ...\Griffin\Binaries\Win64\ue4ss\Mods\SWGRTelemetry\
  (next to README.txt). Open it with a double click.

  The first time Windows may warn you with "Windows protected your PC": that is normal for
  home-made programs without a signature. Click "More info" and "Run anyway".

What it does
  - Reads the mod's files from your disk. It uses no internet and no account.
  - Home: your Arcade events with your record, the #1 target and your best lap.
  - Page of each event: record, target, ideal lap, consistency, how your total time evolves,
    every attempt and the lap analysis (map, gap and speed).
  - Ideal lap: joins the racing line of your best sectors; compare yourself with it on the map
    and in the charts to see where time slips away.
  - Where you lose time: each sector of your last laps against your best time in it,
    from most to least, and how much you would gain by improving the two worst.
  - Replay: plays your lap and the other one on the map at the same time, with pause,
    speed (x1 to x8) and a bar to jump to any moment.
  - Home by planet, with a filter by vehicle and by category (as in the game's Arcade).
  - Your game records are imported by themselves from the Arcade menu (mod v0.9.4 or later).
  - It updates by itself when each lap or event ends: you can keep it open while you play.

Simple mode and Tryhard mode
  "Simple · Tryhard" button at the top (also in the ⚙ menu). Simple: your record, the #1, your
  attempts and the map with the replay of your best lap against a friend, the ideal lap or another
  attempt of yours. Tryhard: the whole analysis (laps and sectors, A/B comparer, charts, where you
  lose time). In Tryhard the event page has two columns and the map stays in view as you scroll.
  To go back home, click "Telemetry" at the top left.

Home: cards or times
  Top right: "Cards" or "Times". The cards carry an illustration of their planet and the vehicle
  icon. In Times you see every event as tiles, several per row, with your record, the game's #1
  time, whether you have the gold (beating the #1) and your best friends' times.

Replay and comparison: always like with like
  Above the map, always in view, is the "A against B" bar: what you compare, who A is, who B is,
  their times and who wins. First you choose what to compare in "Compare":
    Lap: two laps (yours, a friend's best lap or the ideal lap).
    Whole race: two complete races with the same laps (yours or a friend's best).
    Sector S1, S2...: that stretch of the two laps.
  A and B only offer things of that kind (never a lap against a race), and the replay, the charts
  and the table follow your choice (for a whole race, the table goes lap by lap).
  Replay mode: real time or with both cars at the same point. "Follow car" zooms the map in on
  your car; "Lines" draws both racing lines on top of each other.
  A/B comparer (Tryhard): pick A and B and click "Compare". In the laps table, tapping a lap
  puts it in A and its "B" button puts it in B. Lap times are the game's official ones.

Profile and Social: compare yourself with your friends (no internet)
  "Create profile" button at the top: choose your pilot name and your colour (how your friends see you).
  "Social" tab: standings with all your friends, head to head against the one you choose, and your
  files. "Export my times" creates pilot_<name>.swgr in the mod's "shared" folder; send it over
  WhatsApp, Discord or a USB stick. A friend's file: drag it onto the window or "Add file…"
  (it is saved in the "friends" folder). On each event and in the Times view you see yourself
  and your 3 best friends.
  What the file holds: your best time in each event (also the records imported from the game,
  without telemetry, for the standings), the telemetry of your best whole race (all its laps)
  and that of your best lap. In Social, next to each friend, it says how many events their file
  brings and how many with the whole race or with a lap.
  To compare yourself, open an event and in "Against your friends" click:
    "Compare race": their whole race against yours, lap by lap, in the replay.
    "Compare lap": their best lap against yours on the map and in the charts.
    "time only": their file has the time but not the telemetry (a game record or a file from an
    older version: ask them to export again with 0.9.20 or later).
  They are also in the A/B comparer (in B, "Friends" group) and in Simple mode ("against").

About and what's new
  In the ⚙ menu > "About & what's new": versions of the app and of the mod, what is new in each
  version, credits and licences. The first time you open a new version, the app tells you.

Notices
  A notice shows at the top if the mod and the app are not the same version (since 0.9.10 both
  carry the same number; before, the app went by 1.x), and another one if the mod's safe mode
  has turned something off (with the "Try again" button).

Star Wars fonts (optional)
  The app uses SF Distant Galaxy for planet names and SF Distant Galaxy Symbols for
  Aurebesh (the "ES · EN · Aurebesh" button at the top). They are not inside the app: their
  licence does not allow it. To turn them on, install them in Windows (double click the .ttf >
  Install) or create a "fonts" folder next to the app and copy these files there as they are:
    SF Distant Galaxy.ttf
    SF Distant Galaxy Symbols.ttf
  Without them the app works the same, with its normal fonts.

Languages
  Spanish, English and Aurebesh (⚙ menu > Language, or the "ES · EN · Aurebesh" button at the top).
  Aurebesh is written over the English text and needs the SF Distant Galaxy Symbols font.

Themes and effects
  At the top you have the "Theme" button (Sith, Jedi, Imperial or Galactic Racer: each click
  goes to the next one) and the ⚙ menu with the theme, the hologram effect (scan lines, soft,
  normal or strong), the animations, the language and the in-track ghost colour. Everything is
  remembered in preferences.txt.
  The Galactic Racer theme uses Archivo Black and Barlow Semi Condensed (SIL OFL licence,
  included in the app; see FONT_LICENSE_OFL.txt).

Space
  It keeps the telemetry of the last 100 attempts of each event (change it in app.ini,
  attempts_to_keep). The attempts with your best total, best lap, best start and each best sector
  are always kept, so the ideal lap does not change when old attempts are deleted. The times of
  every attempt are kept (summaries are never deleted). Quick restarts of older versions (with no
  lap done) are deleted. Sessions are compressed after 10 minutes to take about 4 times less space.

To close it, close its window.
