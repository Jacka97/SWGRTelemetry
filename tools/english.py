"""Builds the English page (template_en.html) from the Spanish original (template.html); it runs on every build."""
import re
import os
HERE = os.path.dirname(os.path.abspath(__file__))
SPANISH_TEMPLATE = os.path.join(HERE, '..', 'app', 'web', 'template.html')
ENGLISH_TEMPLATE = os.path.join(HERE, '..', 'app', 'web', 'template_en.html')
s = open(SPANISH_TEMPLATE, encoding='utf-8').read()

# 1) Sentences built from parts: rewritten by hand (the word order changes in English)
MANUAL = [
 ("<html lang=\"es\">", "<html lang=\"en\">"),
 ("<title>Telemetría Galactic Racer</title>", "<title>Galactic Racer Telemetry</title>"),
 ("const PAGE_LANGUAGE = 'es';", "const PAGE_LANGUAGE = 'en';"),
 ("const ordinal = number => number + 'º';", "const ordinal = number => number + (number % 100 >= 11 && number % 100 <= 13 ? 'th' : ['th', 'st', 'nd', 'rd'][number % 10] || 'th');"),
 ("pilot: myPilotName() || 'Tú', color: myPilotColor(), total: event.recordTime", "pilot: myPilotName() || 'You', color: myPilotColor(), total: event.recordTime"),
 ("pilot: myPilotName() || 'Tú', color: myPilotColor(), total: myGameRecord.total", "pilot: myPilotName() || 'You', color: myPilotColor(), total: myGameRecord.total"),
 ("const myName = myPilotName() || 'Tú';", "const myName = myPilotName() || 'You';"),
 ("(++prepared) + ' de ' + events.length", "(++prepared) + ' of ' + events.length"),
 ("showToast((wholeRace ? 'La carrera de ' : 'La vuelta de ') + pilot + ' no es del mismo recorrido que la tuya')", "showToast(pilot + (wholeRace ? '\\'s race' : '\\'s lap') + ' is not on the same route as yours')"),
 ("figure(event.plannedLaps === 1 ? 'Mejor con el mod' : 'Mejor vuelta'", "figure(event.plannedLaps === 1 ? 'Mod best' : 'Best lap'"),
 ("""+ myPosition + 'º</span> de ' + rows.length + ' entre amigos</span> · ';""", """+ ordinal(myPosition) + '</span> of ' + rows.length + ' among friends</span> · ';"""),
 ("""'<div class="note">media de tus últimas ' + event.sectorLosses.count + (event.plannedLaps > 1 ? ' vueltas' : ' pasadas') + ' limpias frente a tu mejor tiempo en cada sector' + (event.plannedLaps > 1 ? ' · el S1 de salida va aparte' : '') + '</div>';""",
  """'<div class="note">average of your last ' + event.sectorLosses.count + (event.plannedLaps > 1 ? ' clean laps' : ' clean runs') + ' vs your best time in each sector' + (event.plannedLaps > 1 ? ' · the start S1 is counted separately' : '') + '</div>';"""),
 ("""'<p class="loss-lead">Si igualas tu mejor ' + worstSectors.map(row => 'S' + (row.sectorIndex + 1)).join(' y ') + ', ganas <b class="numeric">' + possibleGain.toFixed(3) +
        ' s</b> por vuelta' + (event.plannedLaps > 1 ? ' (<b class="numeric">' + worstSectors.reduce((sum, row) => sum + row.loss * (row.sectorIndex === 0 ? event.plannedLaps - 1 : event.plannedLaps), 0).toFixed(2) + ' s</b> en el evento)' : '') + '.</p>';""",
  """'<p class="loss-lead">Match your best ' + worstSectors.map(row => 'S' + (row.sectorIndex + 1)).join(' and ') + ' and you gain <b class="numeric">' + possibleGain.toFixed(3) +
        ' s</b> per lap' + (event.plannedLaps > 1 ? ' (<b class="numeric">' + worstSectors.reduce((sum, row) => sum + row.loss * (row.sectorIndex === 0 ? event.plannedLaps - 1 : event.plannedLaps), 0).toFixed(2) + ' s</b> over the event)' : '') + '.</p>';"""),
]
for spanish, english in MANUAL:
    assert s.count(spanish) == 1, ('manual', s.count(spanish), spanish[:80])
    s = s.replace(spanish, english)
# 2) Literals between single quotes: 'español' -> 'english'
LIT = {
 'Centinela 1': 'Sentinel I',
 'Vaina': 'Podracer', 'Contrarreloj': 'Time Trial', 'Moto': 'Bike', 'Coche': 'Car', 'Rasante': 'Skimmer',
 'punto a punto': 'point to point', 'Carrera por equipos': 'Team Race', 'corto': 'short', 'largo': 'long', 'inverso': 'reverse', 'circuito': 'circuit',
 ' (evento sin identificar)': ' (unidentified event)',
 '<a data-navigate="home">Eventos de Arcade</a>': '<a data-navigate="home">Arcade events</a>',
 '<div class="compare-picker simple-only"><label for="simpleRival" id="simpleRivalLabel">Tu mejor vuelta contra</label><select id="simpleRival" aria-label="Contra quién"></select></div>': '<div class="compare-picker simple-only"><label for="simpleRival" id="simpleRivalLabel">Your best lap against</label><select id="simpleRival" aria-label="Against whom"></select></div>',
 'Tu intento del ': 'Your attempt of ', '<option value="">Corre otra vez para tener con quién compararte</option>': '<option value="">Race again to have someone to compare with</option>',
 'nº1 <span class="numeric">': '#1 <span class="numeric">', ' · sin telemetría': ' · no telemetry',
 'Modo Simple y modo Tryhard (botón de arriba): el simple enseña lo esencial y el mapa primero; el tryhard, todo el análisis': 'Simple and Tryhard modes (button at the top): simple shows the essentials with the map first; tryhard, the whole analysis',
 'El análisis del evento en dos columnas: el mapa con la repetición se queda a la vista mientras bajas por las vueltas y las gráficas': 'The event analysis in two columns: the map with the replay stays in view while you scroll through the laps and charts',
 'Barra de arriba más grande, con iconos, y «Telemetría» te devuelve al inicio': 'A bigger top bar with icons, and «Telemetry» takes you back home',
 'Ilustración de cada planeta en las tarjetas e iconos de vehículo junto a cada evento': 'An illustration of each planet on the cards and vehicle icons next to each event',
 'Vista Tiempos en fichas, varias por fila, para ver más eventos sin bajar': 'Times view as tiles, several per row, to see more events without scrolling',
 'Arreglado: al entrar por primera vez en un circuito, el juego en pantalla completa ya no pasa a ventana (el mod abría un instante una ventana de sistema para crear la carpeta del circuito)': 'Fixed: the first time you enter a track, a full-screen game no longer drops to windowed (the mod opened a system window for a moment to create the track folder)',
 'Opciones': 'Options', 'Perfil': 'Profile', 'Tu archivo de piloto': 'Your pilot file', 'Archivos de tus amigos': 'Your friends\\\' files', 'Fantasma en pista': 'In-track ghost',
 'Apariencia de la app': 'App appearance', 'Panel en carrera': 'In-race panel', 'Acerca de': 'About', 'Sector a sector': 'Sector by sector',
 'Tu nombre y tu color, que ven tus amigos en Social.': 'Your name and colour, which your friends see in Social.',
 'Exporta tus tiempos para pasárselos a tus amigos.': 'Export your times to hand them to your friends.',
 'Los archivos .swgr que has añadido para compararte con ellos.': 'The .swgr files you added to compare yourself with them.',
 'Cómo se ve tu fantasma en la carrera; se aplica en la siguiente.': 'How your ghost looks in the race; it applies from the next one.',
 'Tema, modo, efectos e idioma de esta ventana.': 'Theme, mode, effects and language of this window.',
 'Próximamente: opciones del panel de tiempos que se ve en carrera.': 'Coming soon: options for the timing panel shown in the race.',
 'Telemetría Galactic Racer · herramienta no oficial para entrenar los contrarrelojes de Arcade': 'Galactic Racer Telemetry · unofficial tool for training Arcade time trials',
 '<div class="panel-header"><h1>Opciones</h1><span class="muted">Tu perfil, tus archivos de piloto y el aspecto de la app</span></div>': '<div class="panel-header"><h1>Options</h1><span class="muted">Your profile, your pilot files and how the app looks</span></div>',
 '<div><label class="muted" style="font-size:.8rem">Así te ven</label>': '<div><label class="muted" style="font-size:.8rem">How they see you</label>',
 '<div class="drop-zone-header"><label class="button" for="pilotFileInput" tabindex="0">Añadir archivo…</label></div>': '<div class="drop-zone-header"><label class="button" for="pilotFileInput" tabindex="0">Add file…</label></div>',
 '<p class="note">Para compararte con un amigo, entra en un evento: en «Contra tus amigos» pulsa «Comparar carrera» o «Comparar vuelta». En el comparador A/B también aparecen en «Amigos».</p>':
   '<p class="note">To compare yourself with a friend, open an event: in «Against your friends» click «Compare race» or «Compare lap». They also show up under «Friends» in the A/B comparer.</p>',
 '<section class="panel"><div class="empty-state"><b>Aún no tienes amigos añadidos</b><span>Pulsa «Importar / Exportar» arriba (o arrastra aquí un archivo .swgr) y aparecerán la clasificación y el cara a cara. Tu perfil y tu archivo de piloto están en Opciones.</span></div></section>':
   '<section class="panel"><div class="empty-state"><b>No friends added yet</b><span>Click «Import / Export» at the top (or drag a .swgr file here) and the standings and head to head will show up. Your profile and your pilot file are in Options.</span></div></section>',
 'Otros': 'Other', 'Tu récord': 'Your record', 'del juego': 'from the game', 'con el mod': 'with the mod', 'Objetivo nº1': '#1 target',
 'Mejor con el mod': 'Best with the mod', 'Mejor vuelta': 'Best lap', 'ideal ': 'ideal ',
 ' intento · ': ' attempt · ', ' intentos · ': ' attempts · ', 'tramo · ': 'stage · ', ' vueltas · ': ' laps · ', 'último ': 'last ',
 '<div class="panel"><div class="empty-state"><b>Aún no hay carreras grabadas</b>': '<div class="panel"><div class="empty-state"><b>No races recorded yet</b>',
 '<span>Juega un evento de Arcade con el mod activo y aparecerá aquí en cuanto termines.</span>': '<span>Play an Arcade event with the mod enabled and it will show up here as soon as you finish.</span>',
 '<div class="panel-header"><h1>Eventos de Arcade</h1><span class="muted">': '<div class="panel-header"><h1>Arcade events</h1><span class="muted">',
 ' con telemetría · ': ' with telemetry · ', ' solo con récord del juego · ': ' with game record only · ', ' intentos grabados</span></div>': ' attempts recorded</span></div>',
 '<div class="home-tools"><div class="filters" role="group" aria-label="Filtrar por vehículo"><button type="button" data-vehicle-filter="all" aria-pressed="': '<div class="home-tools"><div class="filters" role="group" aria-label="Filter by vehicle"><button type="button" data-vehicle-filter="all" aria-pressed="',
 '">Todos</button>': '">All</button>', 'Vainas': 'Podracers',
 '<span class="planet-group-none">Otros planetas</span>': '<span class="planet-group-none">Other planets</span>',
 ' evento': ' event', ' eventos': ' events',
 '<div class="planet-group-others"><span class="label">Sin telemetría todavía</span><div class="compact-list">': '<div class="planet-group-others"><span class="label">No telemetry yet</span><div class="compact-list">',
 ' intento': ' attempt', ' intentos': ' attempts',
 '<div class="note">Solo eventos de Arcade: el vehículo y la build son fijos y los tiempos se pueden comparar. Las carreras con build variable se graban pero no aparecen aquí. Los récords sin telemetría vienen del juego; corre el evento con el mod para ver sus vueltas y sectores.</div>':
   '<div class="note">Arcade events only: the vehicle and build are fixed, so times are comparable. Races with a custom build are recorded but not shown here. Records without telemetry come from the game; run the event with the mod to see its laps and sectors.</div>',
 'Tramo de una vuelta': 'Single-lap stage', ' vueltas': ' laps', ' intentos en el juego': ' attempts in the game',

 'Mejor pasada con el mod': 'Best run with the mod', 'grabada ': 'recorded ', 'sin vueltas oficiales': 'no official laps',
 'Vuelta ideal': 'Ideal lap', 'margen ': 'margin ', ' s sobre tu mejor': ' s off your best', 'suma de tus mejores sectores': 'sum of your best sectors',
 'Total ideal': 'Ideal total', 
 'vuelta 1 ideal + vuelta ideal en las demás': 'ideal lap 1 + ideal lap for the rest', 'vuelta ideal': 'ideal lap',
 'Constancia': 'Consistency', 'media últimas 10 · ': 'last 10 avg · ', ' sobre tu mejor': ' vs your best', 'media de tus últimas 10 vueltas': 'average of your last 10 laps',
 
 '<button class="button small" id="gameRecordSave">Guardar</button><span class="detail" id="gameRecordMessage">Tus tiempos de antes del mod</span></div>': '<button class="button small" id="gameRecordSave">Save</button><span class="detail" id="gameRecordMessage">Your times from before the mod</span></div>',
 '<label class="detail" for="gameLapInput">Mejor vuelta</label><input id="gameLapInput" placeholder="19.800" value="': '<label class="detail" for="gameLapInput">Best lap</label><input id="gameLapInput" placeholder="19.800" value="',
 '<span class="best">igual</span>': '<span class="best">same</span>',
 '<p class="loss-start"><span class="tag">salida</span> El S1 de la vuelta 1 (sales con menos velocidad) se compara solo con tus otras salidas: tu mejor es <b class="numeric">':
   '<p class="loss-start"><span class="tag">start</span> Lap 1 S1 (you start slower) is only compared with your other starts: your best is <b class="numeric">',
 '</b> y de media en tus últimas ': '</b> and on average over your last ', ' pierdes <b class="numeric loss">+': ' you lose <b class="numeric loss">+',
 
 '<span><i class="legend-line" style="background:var(--accent)"></i>tus eventos completos</span>': '<span><i class="legend-line" style="background:var(--accent)"></i>your completed events</span>',
 '<span><i class="legend-line" style="background:var(--warning)"></i>objetivo nº1</span>': '<span><i class="legend-line" style="background:var(--warning)"></i>#1 target</span>',
 '<span><i class="legend-line" style="background:var(--best)"></i>récord del juego</span>': '<span><i class="legend-line" style="background:var(--best)"></i>game record</span>',
 
 ' por evento; el mejor total y la mejor vuelta se guardan siempre.</span></div><div class="table-scroll"><table><thead><tr><th>Analizar · fecha</th><th>Total</th><th>Objetivo</th>':
   ' per event; your best total and best lap are always kept.</span></div><div class="table-scroll"><table><thead><tr><th>Analyse · date</th><th>Total</th><th>Target</th>',
 
 'grabado antes de identificar eventos': 'recorded before events were identified', 'su telemetría ya no se conserva': 'its telemetry is no longer kept',
 '<span class="tag highlight">récord</span>': '<span class="tag highlight">record</span>', '<span class="tag highlight">mejor vuelta</span>': '<span class="tag highlight">best lap</span>',
 '<span class="tag success">nº1 batido</span>': '<span class="tag success">#1 beaten</span>', '<span class="tag">superado</span>': '<span class="tag">passed</span>', '<span class="tag failure">no superado</span>': '<span class="tag failure">not passed</span>',
 
 
 
 
 '<select id="replaySpeed" aria-label="Velocidad de la repetición"><option value="1">×1</option><option value="2" selected>×2</option><option value="4">×4</option><option value="8">×8</option></select>':
   '<select id="replaySpeed" aria-label="Replay speed"><option value="1">×1</option><option value="2" selected>×2</option><option value="4">×4</option><option value="8">×8</option></select>',
 '<input type="range" id="replayPosition" min="0" max="1000" value="0" aria-label="Momento de la vuelta"><span class="numeric" id="replayTime">0:00.0</span></div>': '<input type="range" id="replayPosition" min="0" max="1000" value="0" aria-label="Point in the lap"><span class="numeric" id="replayTime">0:00.0</span></div>',
 
 '<span class="loss">Usa el formato 1:21.500 o 19.800</span>': '<span class="loss">Use the format 1:21.500 or 19.800</span>',
 'aún sin evento completo': 'no completed event yet', 'récord del juego': 'game record', 'con el mod · ': 'with the mod · ',
 
 
 '<span class="pill success">Nº1 batido · ': '<span class="pill success">#1 beaten · ', '<span class="pill failure">a ': '<span class="pill failure">', ' s del nº1</span>': ' s off #1</span>',
 'Media últimos ': 'Avg of last ',
 
 
 'Guardado': 'Saved', 'No se pudo guardar: ': 'Could not save: ',
 'Aquí verás la evolución de tu tiempo total en cada evento completo.': 'Your total time for each completed event will show here.',
 'objetivo ': 'target ', 'mejor ': 'best ', 'intentos completos, del más antiguo al más reciente →': 'completed attempts, oldest to newest →',
 'Cargando telemetría…': 'Loading telemetry…', 
 'Pasa el ratón por las gráficas para ver cada punto en el mapa.': 'Hover over the charts to see each point on the map.', 'No se pudo cargar la telemetría: ': 'Could not load the telemetry: ',
 '<thead><tr><th>Vuelta</th><th>Tiempo</th>': '<thead><tr><th>Lap</th><th>Time</th>',
 '" data-lap="ideal"><td class="text"><b class="best">Vuelta ideal</b> <span class="muted" title="': '" data-lap="ideal"><td class="text"><b class="best">Ideal lap</b> <span class="muted" title="',
 '">mejores sectores</span></td>': '">best sectors</span></td>', '</b> <span class="muted">su mejor vuelta</span></td>': '</b> <span class="muted">their best lap</span></td>',
 ' vuelta': ' lap', ' · mejor <span class="numeric">': ' · best <span class="numeric">',
 '<span class="tag" title="Vuelta de salida: su S1 se compara solo con otras salidas">salida</span>': '<span class="tag" title="Start lap: its S1 is only compared with other starts">start</span>',
 '<span class="tag failure">incidente</span>': '<span class="tag failure">incident</span>', 'Vuelta ideal · ': 'Ideal lap · ', ' · su mejor vuelta · ': ' · their best lap · ',
 '<b class="gain">va ': '<b class="gain">', ' s por delante</b>': ' s ahead</b>', '<b class="loss">va ': '<b class="loss">', ' s por detrás</b>': ' s behind</b>', 
 'Elige una vuelta de referencia para ver la diferencia.': 'Pick a reference lap to see the gap.', '▶ Repetición': '▶ Replay', '❚❚ Pausa': '❚❚ Pause',
 '<span style="color:var(--gain)">ganas tiempo</span><span class="scale-bar" style="background:linear-gradient(90deg,': '<span style="color:var(--gain)">gaining time</span><span class="scale-bar" style="background:linear-gradient(90deg,',
 ')"></span><span style="color:var(--loss)">pierdes tiempo</span>': ')"></span><span style="color:var(--loss)">losing time</span>',
 '<span>Elige una vuelta de referencia para ver dónde ganas o pierdes.</span>': '<span>Pick a reference lap to see where you gain or lose.</span>',
 'SALIDA': 'START', 'META': 'FINISH', 'DIFERENCIA A − B (s)': 'GAP A − B (s)', 'VELOCIDAD (km/h)': 'SPEED (km/h)',
 'metros desde la salida →': 'metres from the start →', 'metros desde la meta →': 'metres from the line →', ' km/h</span> · dif. <b class="': ' km/h</span> · gap <b class="',
 'el panel de tiempos': 'the timing panel', 'la lectura de tus récords del juego': 'reading your game records', 'la búsqueda de récords (Ctrl+Shift+K)': 'the record search (Ctrl+Shift+K)',
 'la grabación de carreras': 'race recording', 'la grabación': 'recording',
 'la lectura de los nombres de evento del juego': 'reading event names from the game',
 'Código del mod y de la app en inglés claro, sin abreviaturas, para que sea fácil de leer y revisar': 'Mod and app code in plain English, without abbreviations, so it is easy to read and review',
 'Los archivos de la carpeta del mod pasan a tener nombres en inglés (log.txt, game_records.txt, tracks…): se renombran solos la primera vez, sin perder nada':
   'The files in the mod folder now have English names (log.txt, game_records.txt, tracks…): they are renamed automatically the first time, without losing anything',
 'Los archivos de piloto nuevos usan nombres en inglés por dentro; los de tus amigos de versiones anteriores se siguen leyendo': 'New pilot files use English names inside; your friends\\\' files from earlier versions are still read',
 'Repetición de la carrera entera con los dos coches a la vez: contra otro intento tuyo o con la referencia repetida en cada vuelta': 'Whole-race replay with both cars at once: against another attempt of yours or with the reference repeated on every lap',
 ' · carrera entera': ' · whole race', '<optgroup label="Otros intentos (carrera entera)">': '<optgroup label="Other attempts (whole race)">', 'Elige dos cosas distintas': 'Pick two different things',
 'Elige las dos, A y B': 'Pick both, A and B', 'Para comparar carreras enteras, pon en A una carrera o una vuelta tuya': 'To compare whole races, put one of your races or laps in A',
 'Carrera entera': 'Whole race',
 'En el comparador A/B puedes elegir la carrera entera de cualquier intento, aunque no esté marcado': 'In the A/B comparer you can pick the whole race of any attempt, even if it is not ticked',
 'Tatooine y los planetas de las carreras de vainas, reconocidos por el código del evento': 'Tatooine and the podracing planets, recognised by the event code',
 'El tiempo nº1 de cada evento se lee de la clasificación del juego': 'The #1 time of each event is read from the game leaderboard',
 'Perfil de piloto: tu nombre y tu color, que viajan en tu archivo de piloto': 'Pilot profile: your name and colour, which travel inside your pilot file',
 'Pestaña Social: clasificación con todos tus amigos y cara a cara contra el que elijas': 'Social tab: standings with all your friends and head to head against whoever you pick',
 'En los eventos y en la vista Tiempos salen solo tú y tus 3 mejores amigos': 'Events and the Times view show only you and your 3 best friends',
 'Comparador A/B: elige dos vueltas cualesquiera (tuyas, de amigos o la ideal) y pulsa Comparar': 'A/B comparer: pick any two laps (yours, friends\\\' or the ideal one) and press Compare',
 'Las vueltas se muestran con el tiempo oficial del juego y «Comparar vuelta» usa tu mejor vuelta real': 'Laps show the official game time and «Compare lap» uses your best real lap',
 
 '«Comparar carrera» pone su mejor carrera entera frente a la tuya, vuelta a vuelta. ': '«Compare race» puts their best whole race against yours, lap by lap. ',
 
 'Los sectores de esta tabla son los mejores de cada uno, no los de una sola vuelta. ': 'The sectors in this table are each pilot\\\'s best, not those of a single lap. ',
 'Aún no lo has corrido con el mod: córrelo para ver el análisis': 'Not raced with the mod yet: race it to see the analysis',
 '<div class="compare-picker"><label for="compareA">A</label><select id="compareA" aria-label="Vuelta A"></select><label for="compareB">B</label><select id="compareB" aria-label="Vuelta B"></select>': '<div class="compare-picker"><label for="compareA">A</label><select id="compareA" aria-label="Lap A"></select><label for="compareB">B</label><select id="compareB" aria-label="Lap B"></select>',
 '<button type="button" class="button small" id="compareButton">Comparar</button></div>': '<button type="button" class="button small" id="compareButton">Compare</button></div>',
 '<optgroup label="Referencia">': '<optgroup label="Reference">',  
 'Crear perfil': 'Create profile', ' evento con tiempo': ' event with a time', ' eventos con tiempo': ' events with a time', ' oro': ' gold', ' oros': ' golds',
 '<label class="muted" for="profileName" style="font-size:.8rem">Nombre de piloto</label>': '<label class="muted" for="profileName" style="font-size:.8rem">Pilot name</label>',
 '<div class="pilot-row"><input id="profileName" maxlength="40" autocomplete="off" placeholder="Por ejemplo: Darth Tito" value="': '<div class="pilot-row"><input id="profileName" maxlength="40" autocomplete="off" placeholder="For example: Darth Tito" value="',
 '<label class="muted" style="font-size:.8rem">Tu color</label><div class="swatches">': '<label class="muted" style="font-size:.8rem">Your colour</label><div class="swatches">',
 '<p class="note">Se guarda en tu PC y va dentro de tu archivo de piloto, así tus amigos te ven con tu nombre y tu color.</p></div>': '<p class="note">It is saved on your PC and goes inside your pilot file, so your friends see you with your name and colour.</p></div>',
 'Tu nombre': 'Your name',
 '<div class="panel-header"><h1>Social</h1><span class="muted">Tus tiempos frente a los de tus amigos, sin internet: cada uno exporta su archivo de piloto y os lo pasáis por WhatsApp, Discord o un USB.</span></div>': '<div class="panel-header"><h1>Social</h1><span class="muted">Your times against your friends\\\', offline: each of you exports a pilot file and you swap them over WhatsApp, Discord or a USB stick.</span></div>',
 '<span class="muted">eventos ganados</span></div></div><div class="table-scroll"><table class="social"><thead><tr><th>Evento</th><th>': '<span class="muted">events won</span></div></div><div class="table-scroll"><table class="social"><thead><tr><th>Event</th><th>',
 '</tbody></table></div><div class="note">Resaltado, el más rápido de cada evento. Toca un evento para ver la comparación completa, con sectores y la vuelta de cada uno; los que aún no has corrido con el mod no se abren (solo tienes el récord del juego).</div></section>': '</tbody></table></div><div class="note">Highlighted: the fastest in each event. Tap an event to see the full comparison, with sectors and each pilot\\\'s lap; the ones you have not raced with the mod yet do not open (you only have the game record).</div></section>',
 '<section class="panel"><div class="panel-header"><h2>Cara a cara</h2><div class="compare-picker" style="margin:0"><label for="versusPicker">Contra</label><select id="versusPicker">': '<section class="panel"><div class="panel-header"><h2>Head to head</h2><div class="compare-picker" style="margin:0"><label for="versusPicker">Against</label><select id="versusPicker">',
 ' gana</span><span class="win">': ' wins</span><span class="win">', ' gana</span>': ' wins</span>',
 ' eventos en común · ordenados de donde más pierdes a donde más ganas</span></div>': ' events in common · sorted from where you lose most to where you gain most</span></div>',
 '<div class="table-scroll"><table><thead><tr><th>Evento</th><th>': '<div class="table-scroll"><table><thead><tr><th>Event</th><th>',
 '</th><th>Dif.</th></tr></thead><tbody>': '</th><th>Gap</th></tr></thead><tbody>',
 '<p class="muted">Todavía no tenéis eventos en común con tiempo.</p>': '<p class="muted">You have no events in common with a time yet.</p>',
 '<button type="button" class="button" id="pilotExport">Exportar mis tiempos</button>': '<button type="button" class="button" id="pilotExport">Export my times</button>',
 '<span class="loss">Antes crea tu perfil: </span><a data-navigate="profile" href="#">ponte un nombre de piloto</a>.': '<span class="loss">Create your profile first: </span><a data-navigate="profile" href="#">pick a pilot name</a>.',
 '<p class="more-friends muted">Y ': '<p class="more-friends muted">And ', ' amigo más': ' more friend', ' amigos más': ' more friends', ': <a data-navigate="social" href="#">ver todos en Social</a></p>': ': <a data-navigate="social" href="#">see them all in Social</a></p>',
 'Vuelo de prueba': 'Test flight', 'Carreras de vainas': 'Podracing', 'Despegar': 'Take off', 'Precisión': 'Precision', 'Ácido': 'Acid', 'Fuego y hielo': 'Fire and ice', 'Avanzado': 'Advanced',
 'Categoría ': 'Category ',
 '<div class="filters categories" role="group" aria-label="Filtrar por categoría"><button type="button" data-category-filter="all" aria-pressed="': '<div class="filters categories" role="group" aria-label="Filter by category"><button type="button" data-category-filter="all" aria-pressed="',
 '">Todas</button>': '">All</button>',
 'Todos los planetas con su nombre del juego (Crait, Tatooine y los demás), leídos por el mod': 'Every planet with its in-game name (Crait, Tatooine and the rest), read by the mod',
 'Filtro por categoría como en el Arcade del juego: vuelo de prueba, carreras de vainas, precisión, avanzado…': 'Category filter like the game\\\'s Arcade: test flight, podracing, precision, advanced…',
 'El tiempo nº1 y la categoría de cada evento se guardan aunque no cambie tu récord': 'Each event\\\'s #1 time and category are saved even if your record does not change',
 'Repetición nueva: compara un sector, la vuelta o la carrera entera, a tiempo real o con los dos coches en el mismo punto': 'New replay: compare a sector, the lap or the whole race, in real time or with both cars at the same point',
 'Zoom que sigue a tu coche, trazadas superpuestas y coches con etiqueta y distancia en metros': 'Zoom that follows your car, overlaid racing lines, and labelled cars with the distance in metres',
 'Tabla sector a sector bajo el mapa: quién gana cada tramo, y al tocarlo se repite': 'Sector-by-sector table under the map: who wins each segment, and tapping it replays it',
 '«Comparar con»: elige la vuelta ideal, la de un amigo o cualquier vuelta tuya desde un desplegable': '«Compare with»: pick the ideal lap, a friend\\\'s lap or any of your laps from a drop-down',
 'Inicio en vista «Tiempos»: todos los eventos con tu récord, el nº1, el oro y los tiempos de tus amigos': '«Times» view on the home page: every event with your record, the #1, gold and your friends\\\' times',
 'El mod importa también el tiempo nº1 de cada evento y vuelve a leer los nombres en cada partida': 'The mod also imports each event\\\'s #1 time and rereads the names every session',
 'nº1 del juego': 'game #1',
 '<span class="tag gold" title="Batiste el nº1 por ': '<span class="tag gold" title="You beat #1 by ',
 '<span class="loss" title="Te falta para el nº1">': '<span class="loss" title="Still to go for #1">',
 '<div class="table-scroll"><table class="times"><thead><tr><th>Evento</th><th>Tu récord</th><th>Nº1</th><th>Oro</th>': '<div class="table-scroll"><table class="times"><thead><tr><th>Event</th><th>Your record</th><th>#1</th><th>Gold</th>',
 '<th>Intentos</th></tr></thead><tbody>': '<th>Attempts</th></tr></thead><tbody>',
 ' <span class="muted">· sin telemetría</span>': ' <span class="muted">· no telemetry</span>',
 '<div class="gold-count">Oro (batir el nº1): <b>': '<div class="gold-count">Gold (beat #1): <b>', '</b> de ': '</b> of ', ' eventos</div>': ' events</div>',
 '<div class="segmented" role="group" aria-label="Vista"><button type="button" data-home-view="cards" aria-pressed="': '<div class="segmented" role="group" aria-label="View"><button type="button" data-home-view="cards" aria-pressed="',
 '">Tarjetas</button>': '">Cards</button>', '">Tiempos</button></div></div>': '">Times</button></div></div>',
 ' <span class="tag gold">oro</span>': ' <span class="tag gold">gold</span>', ' s">oro</span>': ' s">gold</span>',

 '<div class="analysis-map"><div class="panel map-panel"><div class="panel-header"><h2 style="color:var(--map-text)">Trazada</h2><div class="segmented"><button id="mapSpeedMode" aria-pressed="true">Velocidad</button><button id="mapGainMode" aria-pressed="false">Ganancia</button><button id="mapLinesMode" aria-pressed="false">Trazadas</button><button id="mapTrailMode" class="tryhard-only" aria-pressed="false">Estela</button></div></div>':
   '<div class="analysis-map"><div class="panel map-panel"><div class="panel-header"><h2 style="color:var(--map-text)">Racing line</h2><div class="segmented"><button id="mapSpeedMode" aria-pressed="true">Speed</button><button id="mapGainMode" aria-pressed="false">Gain</button><button id="mapLinesMode" aria-pressed="false">Lines</button><button id="mapTrailMode" class="tryhard-only" aria-pressed="false">Trail</button></div></div>',
 '<div class="versus-bar" id="versusBar"><label class="versus-kind">Comparar <select id="replayScope" aria-label="Qué comparar"><option value="lap">Vuelta</option></select></label>':
   '<div class="versus-bar" id="versusBar"><label class="versus-kind">Compare <select id="replayScope" aria-label="What to compare"><option value="lap">Lap</option></select></label>',
 '<label>Modo <select id="replaySync" aria-label="Cómo se comparan"><option value="realTime">A tiempo real</option><option value="samePoint">En el mismo punto</option></select></label>':
   '<label>Mode <select id="replaySync" aria-label="How they are compared"><option value="realTime">Real time</option><option value="samePoint">At the same point</option></select></label>',
 '<button type="button" class="button small" id="replayFollow" aria-pressed="false">Seguir coche</button></div>': '<button type="button" class="button small" id="replayFollow" aria-pressed="false">Follow car</button></div>',
 '<button type="button" class="button small" id="replayPlay" aria-label="Reproducir">▶ Repetición</button>': '<button type="button" class="button small" id="replayPlay" aria-label="Play">▶ Replay</button>',
 ' repetida en cada vuelta)</span>': ' repeated on every lap)</span>',
 '<optgroup label="Amigos">': '<optgroup label="Friends">',
 '<option value="lap">Vuelta</option>': '<option value="lap">Lap</option>',
 '<option value="race">Carrera entera</option>': '<option value="race">Whole race</option>',
 '">Sector S': '">Sector S',
 'Vuelta': 'Lap', 'Carrera (': 'Race (', ' vueltas)': ' laps)',
 '<table class="sector-table"><thead><tr><th>Tramo</th><th>A</th><th>': '<table class="sector-table"><thead><tr><th>Segment</th><th>A</th><th>',
 '</th><th>Dif.</th><th>Gana</th></tr></thead><tbody>': '</th><th>Gap</th><th>Wins</th></tr></thead><tbody>', '</th><th>A</th><th>B</th><th>Dif.</th><th>Gana</th></tr></thead><tbody>': '</th><th>A</th><th>B</th><th>Gap</th><th>Wins</th></tr></thead><tbody>',
 '" title="Repetir este tramo"><td class="text">': '" title="Replay this segment"><td class="text">',
 '<span class="tag">empate</span>': '<span class="tag">tie</span>',
 'Las dos carreras enteras, vuelta a vuelta. Toca «Carrera» para repetirla.': 'Both whole races, lap by lap. Tap «Race» to replay it.',
 'Toca un tramo para repetirlo: la repetición, el zoom y las gráficas se centran en él.': 'Tap a segment to replay it: the replay, the zoom and the charts centre on it.',
 'En el mismo punto: A lleva <b>': 'At the same point: A is at <b>', ' s</b> y ': ' s</b> and ', '<b class="gain">A gana ': '<b class="gain">A gains ', '<b class="loss">A pierde ': '<b class="loss">A loses ',
 ' de ': ' of ',

 'Fantasma de salida: la vuelta 1 ya guarda su recorrido aunque salgas desde la parrilla, antes de la línea, así que la diferencia en directo funciona también en la salida': 'Start ghost: lap 1 now records its trace even when you start on the grid behind the line, so the live gap works on the start lap too',
 'La diferencia en directo de la salida cuenta desde el mismo instante que el cronómetro del panel': 'The live gap on the start lap counts from the same moment as the panel timer',
 'Diagnóstico de planetas en registro.txt para recuperar los nombres de planeta de los récords del juego': 'Planet diagnostic in registro.txt to recover planet names for the game records',
 'Arreglado el cierre del juego en el menú principal al importar los récords: el mod comprueba que cada texto del juego es de verdad un texto antes de leerlo': 'Fixed the game closing in the main menu while importing records: the mod now checks that each game text really is text before reading it',
 'Modo seguro más fino: si leer los nombres de evento diera problemas, se desactiva solo eso y los tiempos se siguen importando': 'Finer safe mode: if reading event names causes trouble, only that is turned off and times keep being imported',
 'El mod guarda sus mensajes en registro.txt, aunque el juego se cierre de golpe': 'The mod writes its messages to registro.txt, even if the game crashes',
 '<span><b>El mod está desactualizado.</b> Tienes la v': '<span><b>The mod is out of date.</b> You have v', ' y esta app va con la v': ' and this app goes with v',
 ': copia la carpeta <b>Scripts</b> del mismo paquete que la app.</span>': ': copy the <b>Scripts</b> folder from the same package as the app.</span>',
 '<span><b>La app está desactualizada.</b> Tu mod es la v': '<span><b>The app is out of date.</b> Your mod is v', ' y esta app (v': ' and this app (v', ') va con la v': ') goes with v',
 ': usa el GalacticRacerTelemetry.exe del mismo paquete que el mod.</span>': ': use the GalacticRacerTelemetry.exe from the same package as the mod.</span>',
 '<span><b>Modo seguro del mod.</b> ': '<span><b>Mod safe mode.</b> ', 'Se ha desactivado ': 'Turned off ', ' en tu última partida': ' in your last session', ' porque ': ' because ', 'algo falló': 'something failed',
 ' Lo demás sigue funcionando.</span><button type="button" class="button small" id="safeModeRetry">Volver a intentarlo</button>': ' Everything else keeps working.</span><button type="button" class="button small" id="safeModeRetry">Try again</button>',
 '<span><b>Novedades de la ': '<span><b>What\\\'s new in ',
 '<button type="button" class="button small" data-navigate="about">Ver novedades</button><button type="button" class="button small" id="changesSeen">Entendido</button>': '<button type="button" class="button small" data-navigate="about">See what\\\'s new</button><button type="button" class="button small" id="changesSeen">Got it</button>',
 'Hecho: el mod lo volverá a intentar la próxima vez que abras el juego': 'Done: the mod will try again next time you open the game', 'No se pudo: ': 'Could not do it: ',
 'La app, en castellano e inglés (menú ⚙ › Idioma), y el aurebesh escrito sobre el inglés': 'The app in Spanish and English (⚙ menu › Language), with Aurebesh written over the English',
 'Un solo número de versión para la app y el mod: los dos serán la 1.0 cuando estén terminados': 'One version number for the app and the mod: both become 1.0 when they are finished',
 'Pantalla «Acerca de y novedades» (menú ⚙), con versiones, créditos y licencias': '«About & what\\\'s new» screen (⚙ menu), with versions, credits and licences',
 'Aviso de novedades la primera vez que abres una versión nueva': 'A notice the first time you open a new version',
 'Probada con un año de uso intenso (4.200 intentos): abre en un segundo': 'Tested with a year of heavy use (4,200 attempts): opens in a second',
 'El holograma ya no repite la animación de entrada al recargar datos': 'The hologram no longer replays the entrance animation when data reloads',
 'Pilotos: exporta tus tiempos a un archivo .swgr, añade los de tus amigos y compárate evento a evento, sin internet': 'Pilots: export your times to a .swgr file, add your friends\\\' files and compare event by event, offline',
 '«Contra tus amigos» en cada evento, con «Comparar vuelta» en el mapa y las gráficas': '«Against your friends» on each event, with «Compare lap» on the map and charts',
 'Modo seguro del mod: si el juego se cierra de golpe en una parte delicada, esa parte se desactiva y lo demás sigue': 'Mod safe mode: if the game crashes during a sensitive step, that step is turned off and everything else keeps going',
 'Aviso si el mod y la app no son de la misma versión': 'Notice when the mod and the app are not the same version',
 'Holograma en suave, normal o fuerte, con un barrido de luz al encender y sin parpadeos': 'Hologram in soft, normal or strong, with a light sweep when it turns on and no flicker',
 'Filtro «Speeders» que junta coche, moto y rasante': '«Speeders» filter that groups car, bike and skimmer',
 'En los tramos de una vuelta ya no se confunde tu récord con la mejor pasada grabada': 'On single-lap stages your record is no longer mixed up with the best recorded run',
 'Temas Sith, Jedi, Imperial y Galactic Racer, efecto holograma e idioma aurebesh': 'Sith, Jedi, Imperial and Galactic Racer themes, hologram effect and Aurebesh',
 'Pantalla de carga: la app aparece entera cuando están todos los datos': 'Loading screen: the app appears in full once all the data is in',
 'Vehículos por categorías: vainas aparte y los speeders (coche, moto y rasante)': 'Vehicles by category: podracers on their own, and speeders (car, bike and skimmer)',
 'Panel del juego: diferencia en directo frente a tu vuelta de referencia, barras de sector y aviso de récord': 'In-game panel: live gap to your reference lap, sector bars and record notice',
 'La salida se trata aparte: el S1 de la vuelta 1 se compara solo con otras salidas': 'The start is handled separately: lap 1 S1 is only compared with other starts',
 'Antes': 'Before',
 'Récords del juego importados solos desde el menú de Arcade y nombres de evento legibles': 'Game records imported automatically from the Arcade menu, and readable event names',
 'Tramos punto a punto con sectores virtuales': 'Point-to-point stages with virtual sectors',
 'Inicio por planetas, «Dónde pierdes tiempo», vuelta ideal y repetición en el mapa': 'Home grouped by planet, «Where you lose time», ideal lap and replay on the map',
 'Telemetría por vuelta y sector, con mapa de velocidad y gráficas de diferencia': 'Telemetry per lap and sector, with a speed map and gap charts',
 'app y mod van con el mismo número': 'app and mod share one version number', '<span class="gain">va con esta app</span>': '<span class="gain">matches this app</span>',
 '<span class="loss">esta app va con la v': '<span class="loss">this app goes with v', 'no encuentro Scripts\\\\main.lua': 'Scripts\\\\main.lua not found',
 'Carreras': 'Races', 'intentos grabados': 'attempts recorded', 'Amigos': 'Friends', 'Intentos': 'Attempts', 'archivo de piloto': 'pilot file', 'archivos de piloto': 'pilot files',
 '<section class="two-columns"><div class="panel"><div class="panel-header"><h2>Novedades</h2></div><div class="changelog">': '<section class="two-columns"><div class="panel"><div class="panel-header"><h2>What\\\'s new</h2></div><div class="changelog">',
 'Versiones anteriores': 'Earlier versions', 'Primeras versiones': 'First versions', 'Versión ': 'Version ', ' <span class="muted">app y mod</span>': ' <span class="muted">app and mod</span>', 'Antes: ': 'Before: ',
 '<div class="panel"><div class="panel-header"><h2>Créditos y licencias</h2></div><dl class="credits">': '<div class="panel"><div class="panel-header"><h2>Credits and licences</h2></div><dl class="credits">',
 '<dt>Archivo Black y Barlow Semi Condensed</dt><dd>Fuentes del tema Galactic Racer, incluidas en la app con licencia SIL Open Font License 1.1 (ver FONT_LICENSE_OFL.txt).</dd>':
   '<dt>Archivo Black and Barlow Semi Condensed</dt><dd>Fonts for the Galactic Racer theme, included in the app under the SIL Open Font License 1.1 (see FONT_LICENSE_OFL.txt).</dd>',
 '<dt>SF Distant Galaxy (ShyFonts)</dt><dd>Nombres de planeta y aurebesh. No van dentro de la app porque su licencia no lo permite: se usan solo si las tienes instaladas o en la carpeta «fonts».</dd>':
   '<dt>SF Distant Galaxy (ShyFonts)</dt><dd>Planet names and Aurebesh. Not included in the app because their licence does not allow it: they are only used if you have them installed or in the «fonts» folder.</dd>',
 '<dt>UE4SS</dt><dd>El cargador de mods en el que funciona el mod de telemetría.</dd>': '<dt>UE4SS</dt><dd>The mod loader the telemetry mod runs on.</dd>',
 '<dt>MiniMap y LapRecord de N0M4D</dt><dd>De ahí salen las fuentes de datos del juego que lee el mod.</dd>': '<dt>MiniMap and LapRecord by N0M4D</dt><dd>Where the game data sources the mod reads come from.</dd>',
 '<dt>WebView2 y go-webview2</dt><dd>La ventana de la app usa el motor de Edge que ya trae Windows.</dd>': '<dt>WebView2 and go-webview2</dt><dd>The app window uses the Edge engine that comes with Windows.</dd>',
 '</dl><p class="note">Herramienta no oficial hecha por fans, sin relación con Lucasfilm, Disney ni los creadores del juego. Star Wars, STAR WARS: Galactic Racer y los nombres de planetas, vehículos y eventos pertenecen a sus respectivos propietarios.</p></div></section>':
   '</dl><p class="note">Unofficial fan-made tool, not affiliated with Lucasfilm, Disney or the game\\\'s developers. Star Wars, STAR WARS: Galactic Racer and the names of planets, vehicles and events belong to their respective owners.</p></div></section>',
 '<section class="panel"><div class="panel-header"><h2>Importante</h2></div><div class="about-warning">': '<section class="panel"><div class="panel-header"><h2>Important</h2></div><div class="about-warning">',
 'El mod solo funciona en los eventos de <b>Arcade</b>: en la historia y en el multijugador no graba ni muestra nada. UE4SS sigue cargado con el juego en todos los modos, así que antes de jugar al multijugador se recomienda quitar o renombrar <b>dwmapi.dll</b> en la carpeta Win64 del juego (vuelve a dejarlo como estaba para usar el mod). ':
   'The mod only works in <b>Arcade</b> events: in the story and in multiplayer it records and shows nothing. UE4SS is still loaded with the game in every mode, so before playing multiplayer we recommend removing or renaming <b>dwmapi.dll</b> in the Win64 folder of the game (restore it to use the mod). ',
 'El mod solo lee datos del juego: no cambia nada de la partida. La app trabaja solo con tus archivos, en tu PC y sin internet.</div>': 'The mod only reads game data: it changes nothing in your race. The app only works with your files, on your PC, offline.</div>',
 '<p class="note">Carpeta del mod: <span class="numeric">': '<p class="note">Mod folder: <span class="numeric">',
 
 '<div class="table-scroll"><table class="friends"><thead><tr><th>#</th><th>Piloto</th><th>': '<div class="table-scroll"><table class="friends"><thead><tr><th>#</th><th>Pilot</th><th>',
 'Total': 'Total', 'Tiempo': 'Time', '</th><th>Dif.</th>': '</th><th>Gap</th>', '<th>Mejor vuelta</th>': '<th>Best lap</th>',
 ' <span class="tag">tú</span>': ' <span class="tag">you</span>', ' <span class="muted">· archivo del ': ' <span class="muted">· file from ', 'te saca ': 'ahead of you by ', 'le sacas ': 'you are ahead by ',
 '">Comparar vuelta</button>': '">Compare lap</button>', '<span class="muted">sin telemetría</span>': '<span class="muted">no telemetry</span>',
 'Los sectores son los mejores de cada uno, no los de una sola vuelta. ': 'Sectors are each pilot\\\'s best, not those of a single lap. ',
 
 'Marca algún intento tuyo en «Intentos» para compararte con ': 'Tick one of your attempts in «Attempts» to compare yourself with ', 'La vuelta de ': 'The lap of ', ' no es del mismo recorrido que la tuya': ' is not on the same route as yours',
  'Aún no tienes tiempos que exportar.': 'You have no times to export yet.',
 'Preparando ': 'Preparing ', '<b>Listo:</b> ': '<b>Done:</b> ',
 ' con la carrera entera, ': ' with the whole race, ', ' con la mejor vuelta, ': ' with the best lap, ', ' solo con el tiempo) en <span class="numeric">': ' with the time only) in <span class="numeric">',
 '</span>. Te he abierto la carpeta: pásaselo a tus amigos.': '</span>. The folder is open: send it to your friends.', '<span class="loss">No se pudo guardar: ': '<span class="loss">Could not save: ',
 'Eso no es un archivo de piloto (.swgr)': 'That is not a pilot file (.swgr)', 'Añadido: ': 'Added: ', 'No se pudo añadir ': 'Could not add ',
 
 'Lleva tu mejor tiempo de cada evento (total, mejor vuelta y sectores, también los récords importados del juego) y la telemetría de tu mejor carrera entera, de tu mejor vuelta y de tu mejor vuelta 1 (salida): velocidad y trazada. Se guarda en la carpeta <b>shared</b> del mod. No lleva nada más de tu PC.':
   'It holds your best time in each event (total, best lap and sectors, also the records imported from the game) and the telemetry of your best whole race, of your best lap and of your best lap 1 (start): speed and racing line. It is saved in the mod\\\'s <b>shared</b> folder. Nothing else from your PC goes in it.',
 ' · archivo del ': ' · file from ', ' con carrera entera': ' with the whole race', ' con vuelta': ' with a lap', '">Quitar</button></div>': '">Remove</button></div>',
 '<p class="muted">Todavía no tienes ninguno. Arrastra aquí un archivo <b>.swgr</b> o pulsa «Añadir archivo…».</p>': '<p class="muted">None yet. Drag a <b>.swgr</b> file here or click «Add file…».</p>',
 '<section class="panel"><div class="panel-header"><h2>Clasificación</h2><div class="wins">': '<section class="panel"><div class="panel-header"><h2>Standings</h2><div class="wins">',
 
 
 'Quitado ': 'Removed ',
 '<div class="panel"><div class="empty-state"><b>No encuentro la carpeta del mod</b><span>Copia esta app dentro de la carpeta SWGRTelemetry (junto a README.txt) y vuelve a abrirla.</span></div></div>':
   '<div class="panel"><div class="empty-state"><b>Mod folder not found</b><span>Copy this app into the SWGRTelemetry folder (next to README.txt) and open it again.</span></div></div>',
 'Nueva sesión grabada': 'New session recorded', 'Leyendo tus carreras…': 'Reading your races…',
 '<div class="panel"><div class="empty-state"><b>No se pudieron leer los datos</b><span>': '<div class="panel"><div class="empty-state"><b>Could not read the data</b><span>',
 # 0.9.20: whole races of your friends and times without telemetry
 ' · carrera entera · ': ' · whole race · ', ' · mejor vuelta · ': ' · best lap · ', ' · su carrera, V': ' · their race, V', 'La carrera de ': 'The race of ',
 '">Comparar carrera</button> ': '">Compare race</button> ', '<span class="muted">solo tiempo</span>': '<span class="muted">time only</span>',
 'Tu mejor carrera no tiene telemetría grabada con el mod': 'Your best race has no telemetry recorded with the mod',
 '«Comparar carrera» pone su mejor carrera entera frente a la tuya, vuelta a vuelta, en la repetición y en las gráficas. Los sectores son los mejores de cada uno, no los de una sola vuelta. ':
   '«Compare race» puts their best whole race against yours, lap by lap, in the replay and the charts. Sectors are each pilot\\\'s best, not those of a single lap. ',
 '«Solo tiempo»: su archivo trae el tiempo pero no la telemetría (récords importados del juego o un archivo de una versión anterior). ':
   '«Time only»: their file has the time but not the telemetry (records imported from the game, or a file from an older version). ',
 'Tu archivo de piloto lleva ahora tu mejor carrera entera, vuelta a vuelta, además de tu mejor vuelta: tus amigos pueden comparar la carrera completa contigo («Comparar carrera» y, en el comparador A/B, en «Amigos»)':
   'Your pilot file now holds your best whole race, lap by lap, as well as your best lap: your friends can compare the whole race with you («Compare race» and, in the A/B comparer, under «Friends»)',
 'También lleva los tiempos de los eventos que solo tienen el récord importado del juego, sin telemetría, para que la clasificación con tus amigos tenga todos los eventos':
   'It also holds the times of the events that only have the record imported from the game, without telemetry, so the standings with your friends cover every event',
 'En Social se ve qué trae el archivo de cada amigo: cuántos eventos, cuántos con la carrera entera y cuántos con la vuelta':
   'Social shows what each friend\\\'s file holds: how many events, how many with the whole race and how many with the lap',
 # 0.9.21: like with like, and the A-against-B bar
 ' · su mejor carrera · ': ' · their best race · ', 'Tu carrera del ': 'Your race of ', 'Tu mejor carrera contra': 'Your best race against', 'Tu mejor vuelta contra': 'Your best lap against',
 'Corre otra carrera entera o añade el archivo de un amigo': 'Race another whole race or add a friend\\\'s file', 'Corre otra vez para tener con quién compararte': 'Race again to have someone to compare with',
 'Vuelta ideal (tus mejores sectores)': 'Ideal lap (your best sectors)', ' · su mejor carrera': ' · their best race', ' · su mejor vuelta': ' · their best lap',
 'Tú · ': 'You · ', 'Tú · carrera del ': 'You · race of ', ' (tu mejor)': ' (your best)', 'Tú · V': 'You · V', ' del ': ' of ', ' (tu mejor vuelta)': ' (your best lap)',
 'ninguna carrera con las mismas vueltas': 'no race with the same laps', 'elige con quién': 'pick who', 'gana por ': 'wins by ', 'pierde por ': 'loses by ',
 'Vuelta a vuelta': 'Lap by lap', 'la búsqueda de fantasmas (Ctrl+Shift+G)': 'the ghost search (Ctrl+Shift+G)', 'la prueba del fantasma en pista': 'the in-track ghost test', 'el fantasma en pista': 'the in-track ghost', 'Fantasma en pista: una esfera recorre la carrera entera más rápida del evento, la tuya o la de tu amigo más rápido, para comparar trazadas mientras corres. Tu fantasma se guarda al terminar cada evento cuando mejoras tu total': 'In-track ghost: a sphere runs the fastest whole race of the event, yours or your fastest friend\\\'s, so you can compare racing lines while you race. Your ghost is saved at the end of each event when you improve your total', 'Fantasma en pista: un holograma de tu vehículo recorre la carrera entera más rápida del evento, la tuya o la de tu amigo más rápido, para comparar trazadas mientras corres. Tu fantasma se guarda al terminar cada evento cuando mejoras tu total': 'In-track ghost: a hologram of your vehicle runs the fastest whole race of the event, yours or your fastest friend\\\'s, so you can compare racing lines while you race. Your ghost is saved at the end of each event when you improve your total', 'El mod solo graba y muestra el panel en el Arcade. Los reinicios rápidos (antes de 20 s) cuentan como intento pero no guardan archivos': 'The mod only records and shows the panel in Arcade. Quick restarts (before 20 s) count as an attempt but save no files', 'Espacio: la telemetría de los 100 intentos más recientes de cada evento, y siempre la de tus mejores (total, vuelta, salida y cada mejor sector), así la vuelta ideal no cambia al borrar intentos viejos. Los tiempos de todos los intentos se conservan': 'Space: the telemetry of the 100 most recent attempts of each event, and always that of your bests (total, lap, start and each best sector), so the ideal lap does not change when old attempts are deleted. The times of every attempt are kept', 'El archivo para tus amigos lleva la altura y la dirección de tu vehículo, para su fantasma de ti': 'The file for your friends carries the height and heading of your vehicle, for their ghost of you', 'Color del fantasma en pista': 'In-track ghost colour', 'Cian': 'Cyan', 'Blanco': 'White', 'Rojo': 'Red', 'Verde': 'Green', 'Dorado': 'Gold', 'Morado': 'Purple', 'Color del fantasma en el menú ⚙ (cian, blanco, rojo, verde, dorado o morado); se aplica en la siguiente carrera': 'Ghost colour in the ⚙ menu (cyan, white, red, green, gold or purple); it applies from the next race', 'El fantasma se guarda aunque no hayas abierto todavía la app (antes se perdía si faltaba la carpeta race_ghosts)': 'The ghost is saved even if you have not opened the app yet (before, it was lost when the race_ghosts folder was missing)', 'Tu archivo de piloto lleva tu fantasma de cada evento tal cual: tus amigos ven tu carrera entera desde la salida, con su altura y giros. Los fantasmas de amigos salen solo de archivos exportados con esta versión (los rehechos con vueltas iban desfasados en la salida)': 'Your pilot file carries your ghost of each event as it is: your friends see your whole race from the start, with its height and turns. Friend ghosts only come from files exported with this version (those rebuilt from laps were out of step at the start)', 'el aspecto del fantasma': 'the look of the ghost', 'copiar tu vehículo para el fantasma': 'copying your vehicle for the ghost', 'el diagnóstico de estados del vehículo': 'the vehicle state diagnostics', 'la estela del fantasma': 'the ghost trail', 'Estela detrás del fantasma: naranja con la postcombustión, azul con el ramjet y roja en las frenadas fuertes (la app completa tus fantasmas de antes con el boost de su carrera)': 'Trail behind the ghost: orange with the afterburner, blue with the ramjet and red under hard braking (the app fills your earlier ghosts with the boost of their race)', 'Carpeta del mod ordenada: config (ajustes), data (récords y mejores tiempos), logs (registro y diagnósticos) y docs (guías). La app y el mod mueven tus archivos solos': 'Mod folder tidied up: config (settings), data (records and best times), logs (log and diagnostics) and docs (guides). The app and the mod move your files by themselves', 'Los fantasmas guardan la postcombustión y el ramjet (la app completa los de antes con el boost de su carrera), para la estela que vendrá': 'Ghosts save the afterburner and the ramjet (the app fills the earlier ones with the boost of their race), for the trail to come', 'Panel: en los tramos de una vuelta el tiempo cuenta desde la salida (algunos empiezan el cronómetro de vuelta tras una carrerilla)': 'Panel: on one-lap stages the time counts from the start (some start the lap clock after a run-up)', 'Holograma: sus piezas se recolocan en la salida (en salidas en cuesta la moto se quedaba de pie)': 'Hologram: its pieces are placed again at the start (on uphill starts the bike stayed upright)', 'Comparar: la barra A contra B ya no se mueve al cambiar entre normal, postcombustión y ramjet': 'Compare: the A against B bar no longer moves when switching between normal, afterburner and ramjet', 'Diagnóstico del vehículo en logs\\\\state_samples.txt (para preparar la estela de derrape, canto y frenos); si el juego se cierra, se desactiva solo': 'Vehicle diagnostics in logs\\\\state_samples.txt (to prepare the drift, knife-edge and brake trail); if the game closes, it turns itself off', 'Quitados Ctrl+Shift+G y la esfera de prueba de la 0.9.28 (dejaban los controles del juego enganchados)': 'Removed Ctrl+Shift+G and the 0.9.28 test sphere (they left the game controls stuck)', 'Fantasma en pista: estela desde sus toberas (naranja con la postcombustión, azul con el ramjet) y la llama del motor del juego, que se activan y ajustan en Opciones': 'In-track ghost: a trail from its nozzles (orange with the afterburner, blue with the ramjet) and the engine flame of the game, turned on and adjusted in Options', 'Tramos con carrerilla (la vuelta del juego empieza en una puerta después de salir): el tiempo cuenta desde la salida, el S1 va de la salida a la puerta y los demás sectores hasta la meta, así suman el total del juego. Tus mejores tiempos anteriores de esos tramos empiezan de cero': 'Stages with a run-up (the lap of the game starts at a gate after the start): the time counts from the start, S1 goes from the start to the gate and the other sectors to the finish, so they add up to the total of the game. Your earlier best times on those stages start from zero', 'Precisión: vueltas, sectores, panel y diferencia en vivo descuentan el tiempo que restan los puntos, y el resumen dice cuántos puntos pasaste en cada vuelta y sector. Las carreras de Precisión de antes solo cuentan por su total': 'Precision: laps, sectors, panel and live difference take off the time the points subtract, and the summary says how many points you passed in each lap and sector. Earlier Precision races only count by their total', 'Arreglados los tirones que iban a más cuanto más rato jugabas: mover el fantasma gastaba memoria en cada fotograma': 'Fixed the stutters that got worse the longer you played: moving the ghost used up memory every frame', 'Quitados los diagnósticos (diagnostics.txt, state_samples.txt, effects.txt y Ctrl+Shift+K)': 'Removed the diagnostics (diagnostics.txt, state_samples.txt, effects.txt and Ctrl+Shift+K)', 'Tramos con la puerta antes del GO, o que parecen circuito y son una sola pasada (Carreras frescas, Arena de la muerte): el tiempo y el mapa ya salen bien': 'Stages with the gate before the GO, or that look like a circuit but are a single pass (Carreras frescas, Arena de la muerte): time and map are now right', 'Precisión con carrerilla: los puntos ya no se descuentan dos veces': 'Precision with a run-up: points are no longer discounted twice', 'Precisión: la app marca los puntos que te saltaste en el mapa y en la gráfica de velocidad (tryhard), y la repetición ya no va a saltos': 'Precision: the app marks the points you missed on the map and the speed chart (tryhard), and the replay no longer jumps', 'Mapa: zoom con la rueda, arrastrar para moverlo y doble clic para volver a la vista entera': 'Map: zoom with the wheel, drag to move it and double click to see all of it again', 'Columnas de la página del evento plegables hacia su lado, y recuadro de Comparar plegable': 'Event page columns fold to their side, and the Compare box can be folded', 'Portada con una fila por planeta que se desplaza de lado': 'Home page with one row per planet that scrolls sideways', 'Holograma renovado: tarjetas, paneles y botones flotando sin caja, con opciones para la luz de los botones y del fondo': 'Renewed hologram: cards, panels and buttons floating without a box, with options for the light on buttons and background', 'Opciones con iconos, y ventana rápida para importar o exportar tiempos': 'Options with icons, and a quick window to import or export times', 'Modo simple: Intentos y Amigos en un solo panel con pestañas': 'Simple mode: Attempts and Friends in one panel with tabs', 'El nombre de los eventos ya no se puede cambiar: es siempre el del juego': 'Event names can no longer be changed: they are always the ones from the game', '<section class="panel event-center tryhard-only"><div class="panel-header center-header"><h2>Análisis</h2></div><div class="focus-info" id="focusInfo">': '<section class="panel event-center tryhard-only"><div class="panel-header center-header"><h2>Analysis</h2></div><div class="focus-info" id="focusInfo">', ' puntos pasados de ': ' points passed out of ', ' · saltados: ': ' · missed: ', 'Barra de arriba': 'Top bar', 'Títulos': 'Titles', 'Nombres': 'Names', 'Tiempos': 'Times', 'Sin correr': 'Not raced yet', 'Mejor sector': 'Best sector', 'Mejora': 'Improves', 'Empeora': 'Worsens', 'Ganas': 'You gain', 'Pierdes': 'You lose', 'Fondo': 'Background', 'Gris': 'Grey', 'Diferencia en vivo': 'Live difference', 'Barras de sectores': 'Sector bars', 'Última vuelta': 'Last lap', 'Mejor vuelta': 'Best lap', 'Vuelta ideal': 'Ideal lap', 'Velocidades': 'Speeds', 'Total': 'Total', 'Previsto': 'Forecast', 'Objetivo': 'Target', '<div class="race-panel-screen" id="racePanelScreen"><div class="race-panel-stage" id="racePanelStage"><div class="race-panel-preview" id="racePanelPreview" title="Arrástralo para colocarlo"></div></div></div>': '<div class="race-panel-screen" id="racePanelScreen"><div class="race-panel-stage" id="racePanelStage"><div class="race-panel-preview" id="racePanelPreview" title="Drag it to place it"></div></div></div>', '<p class="note">Arrastra el panel en la pantalla de muestra para colocarlo. Los cambios se aplican en la siguiente carrera.</p>': '<p class="note">Drag the panel on the sample screen to place it. Changes apply from the next race.</p>', '<div class="group"><span>Colocar en</span><div class="options">': '<div class="group"><span>Place at</span><div class="options">', 'Arriba a la izquierda': 'Top left', 'Arriba en el centro': 'Top centre', 'Arriba a la derecha': 'Top right', 'A la izquierda': 'Left', 'A la derecha': 'Right', 'Abajo a la izquierda': 'Bottom left', 'Abajo a la derecha': 'Bottom right', '<div class="group"><span>Tamaño</span><input type="range" id="racePanelScale" min="0.6" max="2.2" step="0.05"><span class="muted" id="racePanelScaleText"></span></div>': '<div class="group"><span>Size</span><input type="range" id="racePanelScale" min="0.6" max="2.2" step="0.05"><span class="muted" id="racePanelScaleText"></span></div>', '<div class="group"><span>Opacidad del fondo</span><input type="range" id="racePanelOpacity" min="0" max="1" step="0.05"><span class="muted" id="racePanelOpacityText"></span></div>': '<div class="group"><span>Background opacity</span><input type="range" id="racePanelOpacity" min="0" max="1" step="0.05"><span class="muted" id="racePanelOpacityText"></span></div>', '<div class="group"><span>Estilo</span><div class="options" data-race-panel-key="style">': '<div class="group"><span>Style</span><div class="options" data-race-panel-key="style">', 'Normal': 'Normal', 'Compacto': 'Compact', '<div class="group"><span>Al empezar la carrera</span><div class="options" data-race-panel-key="enabled">': '<div class="group"><span>When the race starts</span><div class="options" data-race-panel-key="enabled">', 'Se ve': 'Shown', 'Oculto (Ctrl+F10)': 'Hidden (Ctrl+F10)', '<div class="group"><span>Sectores comparados con</span><div class="options" data-race-panel-key="compare_with">': '<div class="group"><span>Sectors compared with</span><div class="options" data-race-panel-key="compare_with">', 'Tu mejor sector': 'Your best sector', 'La vuelta anterior': 'The previous lap', '<div class="group"><span>Filas</span><div class="options race-panel-rows">': '<div class="group"><span>Rows</span><div class="options race-panel-rows">', '<div class="group"><span>Colores</span><div class="options">': '<div class="group"><span>Colours</span><div class="options">', 'Panel guardado: se aplica en la siguiente carrera': 'Panel saved: it applies from the next race', 'No se pudo guardar el panel: ': 'Could not save the panel: ', '">VUELTA 2</span>': '">LAP 2</span>', 'ÚLTIMA': 'LAST', 'MEJOR': 'BEST', 'IDEAL': 'IDEAL', 'VEL.': 'SPEED', 'TOTAL': 'TOTAL', 'PREVISTO': 'FORECAST', 'OBJETIVO': 'TARGET', 'Dónde se ve el panel de tiempos en la carrera, su tamaño, sus colores y sus filas.': 'Where the timing panel shows in the race, its size, its colours and its rows.', '<span><i class="legend-line" style="background:#ffffff"></i> estela blanca</span><span><i class="legend-line" style="background:var(--loss)"></i> freno</span>': '<span><i class="legend-line" style="background:#ffffff"></i> white trail</span><span><i class="legend-line" style="background:var(--loss)"></i> braking</span>',
 'Prueba para el fantasma en pista: Ctrl+Shift+G busca si el juego tiene su propio sistema de fantasmas, y en la primera carrera de cada sesión aparece una esfera delante de ti para comprobar que el juego acepta objetos del mod':
   'Test for an in-track ghost: Ctrl+Shift+G looks for the game\\\'s own ghost system, and in the first race of each session a sphere shows up ahead of you to check that the game takes objects from the mod',
 'Panel del juego más completo: velocidad punta y mínima de la vuelta, total previsto a tu ritmo frente al objetivo, y en IDEAL lo que te dejas en la vuelta frente a tus mejores sectores':
   'A fuller in-game panel: top and minimum speed of the lap, forecast total at your pace against the target, and in IDEAL what you are leaving on the lap against your best sectors',
 'El objetivo del panel es el más rápido entre tu amigo que te gana, tu récord y el nº1 del juego, con su nombre (la app lo pasa al mod desde los archivos de tus amigos)':
   'The panel target is the fastest of your friend who beats you, your record and the game\\\'s #1, with their name (the app passes it to the mod from your friends\\\' files)',
 'Ramjet y postcombustión: el mod los graba en cada carrera y en la repetición se ve en todo momento qué usa cada uno (etiqueta junto a A y B, y junto a cada coche en el mapa cuando lo usa). Las carreras grabadas antes no lo tienen':
   'Ramjet and afterburner: the mod records them in every race and the replay shows at every moment what each one is using (a tag next to A and B, and next to each car on the map while it uses one). Races recorded before do not have it', 'Postcombustión': 'Afterburner',
 'Comparador en un solo bloque encima del mapa: primero qué comparas (vuelta lanzada, vuelta 1 de salida, carrera entera o un sector) y luego A y B, que se aplican al momento':
   'The comparer is one block above the map: first what you compare (flying lap, lap 1 from the start, whole race or a sector) and then A and B, applied at once',
 'La vuelta 1 (salida) va aparte: se compara solo con otras vueltas 1 y tiene su propia vuelta 1 ideal; la vuelta ideal usa solo vueltas lanzadas':
   'Lap 1 (the start) is separate: it is only compared with other laps 1 and has its own ideal lap 1; the ideal lap only uses flying laps',
 'Todos los paneles se pueden plegar con el botón de su cabecera, y la app lo recuerda': 'Every panel can be folded with the button in its header, and the app remembers it',
 'Tu archivo de piloto lleva también tu mejor vuelta 1 (salida); en Social, tus archivos van arriba del todo': 'Your pilot file also carries your best lap 1 (start); in Social, your files come first', ' · su mejor vuelta 1': ' · their best lap 1',
 '<div class="versus-side"><i class="legend-line" id="legendLineB" style="background:var(--reference)"></i><span class="versus-tag">B</span><select id="compareB" class="tryhard-only" aria-label="B"></select><select id="simpleRival" class="simple-only" aria-label="Contra quién"></select><b id="selectedB" class="visually-hidden">—</b><div class="versus-sub"><span class="numeric" id="selectedTimeB"></span><span class="versus-gap" id="versusGap"></span><span class="boost-tag" id="boostTagB" style="visibility:hidden"></span></div></div>': '<div class="versus-side"><i class="legend-line" id="legendLineB" style="background:var(--reference)"></i><span class="versus-tag">B</span><select id="compareB" class="tryhard-only" aria-label="B"></select><select id="simpleRival" class="simple-only" aria-label="Against whom"></select><b id="selectedB" class="visually-hidden">—</b><div class="versus-sub"><span class="numeric" id="selectedTimeB"></span><span class="versus-gap" id="versusGap"></span><span class="boost-tag" id="boostTagB" style="visibility:hidden"></span></div></div>',
 ' · su vuelta 1 · ': ' · their lap 1 · ', 'Vuelta 1 ideal · ': 'Ideal lap 1 · ', 'Tu salida del ': 'Your start of ', 'Vuelta 1 ideal (tus mejores salidas)': 'Ideal lap 1 (your best starts)',
 ' · su vuelta 1': ' · their lap 1', 'Tú · V1 (salida) del ': 'You · V1 (start) of ', 'Diferencia y velocidad en la vuelta 1 (salida)': 'Gap and speed on lap 1 (start)',
 ' · su vuelta ': ' · their lap ', 'Tus carreras': 'Your races', 'Tu vuelta ': 'Your lap ', 'Diferencia y velocidad en la vuelta ': 'Gap and speed on lap ', '">Vuelta ': '">Lap ', '<option value="start">Vuelta 1 (salida)</option>': '<option value="start">Lap 1 (start)</option>', '<button type="button" class="fold-button" data-fold-panel="1" title="Plegar o desplegar">': '<button type="button" class="fold-button" data-fold-panel="1" title="Fold or unfold">',
 'La vuelta ideal ya no da saltos entre sectores: cada sector se ajusta a su tiempo oficial, las trazadas se unen suavemente y no se usan vueltas con incidente':
   'The ideal lap no longer jumps between sectors: each sector is fitted to its official time, the racing lines join smoothly and laps with an incident are not used',
 'Carrera ideal: en «Comparar · Carrera entera» puedes poner en B tu carrera ideal (tu mejor salida en la vuelta 1 y tu vuelta ideal en las demás)':
   'Ideal race: in «Compare · Whole race» you can put your ideal race in B (your best start on lap 1 and your ideal lap on the others)', 'Vuelta 1 ideal': 'Ideal lap 1', 'Carrera ideal': 'Ideal race', 'Carrera ideal · ': 'Ideal race · ',
 'Carrera ideal (tu mejor salida y tus mejores vueltas)': 'Ideal race (your best start and your best laps)',
 'Arreglado: con la app abierta, la primera carrera en un circuito nuevo dejaba de cargarse al pasar a su carpeta (solo salía el rival al comparar y la repetición no iba hasta reiniciar la app)':
   'Fixed: with the app open, the first race on a new circuit stopped loading once it was moved into its folder (only the rival showed up when comparing and the replay did not work until the app was restarted)',
 'No se pudo cargar la telemetría de tus intentos. Cierra y vuelve a abrir la app; si sigue, guarda log.txt y la carpeta tracks para revisarlo.':
   'Could not load the telemetry of your attempts. Close and reopen the app; if it keeps happening, keep log.txt and the tracks folder so it can be checked.',
 'El panel del juego sale en el idioma de la app (en inglés si la app está en inglés o aurebesh) y las guías vienen también en inglés (README_EN, README_app_EN, TESTING_EN)':
   'The in-game panel follows the app\\\'s language (English when the app is in English or Aurebesh) and the guides now also come in English (README_EN, README_app_EN, TESTING_EN)',
 'Panel del juego: en un circuito nuevo, la diferencia en directo (DIF) de la vuelta 1 aparece ya desde la segunda carrera (antes, desde la tercera)':
   'In-game panel: on a new circuit, the live difference (DIF) on lap 1 now shows from the second race (before, from the third)',
 'Textos más claros: «Comparar vuelta» y «Comparar carrera» dicen dónde verlo en cada modo, «resaltado» en vez de «en verde» (el color cambia con el tema) y Social avisa de los eventos que aún no has corrido con el mod':
   'Clearer texts: «Compare lap» and «Compare race» say where to see it in each mode, «highlighted» instead of «green» (the colour changes with the theme) and Social tells you about the events you have not raced with the mod yet',
 'Siempre se compara lo mismo con lo mismo: primero eliges qué comparar (vuelta, carrera entera o un sector) y A y B solo ofrecen cosas de ese tipo; ya no hay vuelta contra carrera ni vuelta repetida en cada vuelta':
   'Always like with like: first you pick what to compare (lap, whole race or a sector) and A and B only offer things of that kind; no more lap against race or a lap repeated on every lap',
 'Barra «A contra B» encima del mapa, siempre a la vista y en los dos modos: quién es A, quién es B, sus tiempos y quién gana':
   'An «A against B» bar over the map, always in view and in both modes: who A is, who B is, their times and who wins',
 'Las gráficas y la tabla siguen a lo que comparas: la carrera entera con sus vueltas marcadas (y la tabla vuelta a vuelta) o solo el sector elegido':
   'The charts and the table follow what you compare: the whole race with its laps marked (and the table lap by lap) or just the chosen sector',
 'Lo que antes se llamaba «ref» ahora es «B» en todas partes': 'What used to be called «ref» is now «B» everywhere', 'Tramo': 'Segment', 'Diferencia y velocidad a lo largo de la carrera': 'Gap and speed along the race', 'Diferencia y velocidad en el sector ': 'Gap and speed in sector ',
 'Diferencia y velocidad a lo largo de la vuelta': 'Gap and speed along the lap',
 'Elige en B otra carrera entera para ver la diferencia.': 'Pick another whole race in B to see the gap.', 'Elige B para ver la diferencia.': 'Pick B to see the gap.',
 '<optgroup label="Tú · ': '<optgroup label="You · ', '<optgroup label="Tus carreras">': '<optgroup label="Your races">',
 '<optgroup label="Otras carreras tuyas (se cargan al comparar)">': '<optgroup label="Other races of yours (loaded when you compare)">',
 'Esas dos carreras no tienen las mismas vueltas': 'Those two races do not have the same laps',
 'Cargando fuentes…': 'Loading fonts…',
 # Página del evento en tres columnas
 'Vueltas y sectores': 'Laps and sectors', 'Dónde pierdes tiempo': 'Where you lose time', 'Gráficas': 'Charts', 'Progreso': 'Progress',
 '<p class="muted">Aún no hay carreras completas en este evento</p>': '<p class="muted">No complete races in this event yet</p>',
 '<div class="note" title="La vuelta ideal une tus mejores sectores entre los intentos marcados, con su trazada: compárate con ella para ver dónde se te escapa el tiempo.">Toca una vuelta para ponerla en A y «B» para compararla con A.</div></div>':
   '<div class="note" title="The ideal lap joins your best sectors from the ticked attempts, with their racing line: compare yourself with it to see where time slips away.">Tap a lap to put it in A and «B» to compare it against A.</div></div>',
 '<div class="tab-pane" data-pane="progress"><div class="pane-header"><h2>Progreso del tiempo total</h2><div class="legend">': '<div class="tab-pane" data-pane="progress"><div class="pane-header"><h2>Total time progress</h2><div class="legend">',
 'Objetivo nº1 · ': '#1 target · ', 'frente a tu récord <span class="': 'vs your record <span class="',
 '<div class="strip-item strip-game tryhard-only"><span class="label">Récord del juego (a mano)</span>': '<div class="strip-item strip-game tryhard-only"><span class="label">Game record (manual)</span>',
 '<table class="loss-table"><thead><tr><th>Sector</th><th>Pérdida</th><th>Tu mejor</th><th>En tu mejor vuelta</th></tr></thead><tbody>':
   '<table class="loss-table"><thead><tr><th>Sector</th><th>Loss</th><th>Your best</th><th>In your best lap</th></tr></thead><tbody>',
 '<section class="panel attempts-panel"><div class="panel-header"><h2>Intentos</h2><span class="muted" title="Pulsa un intento para ver sus datos y marca la casilla para sumar otros al análisis. Se conservan los últimos ':
   '<section class="panel attempts-panel"><div class="panel-header"><h2>Attempts</h2><span class="muted" title="Click an attempt to see its data and tick the box to add others to the analysis. Telemetry is kept for the last ',
 ' por evento; el mejor total y la mejor vuelta se guardan siempre.">Pulsa uno para analizarlo</span></div><div class="attempt-list">':
   ' per event; your best total and best lap are always kept.">Click one to analyse it</span></div><div class="attempt-list">',
 '</div><div class="note">* Total calculado sumando las vueltas oficiales. ! = vuelta con incidente (choque o retroceso). En gris: sin telemetría.</div></section>':
   '</div><div class="note">* Total worked out by adding up the official laps. ! = lap with an incident (crash or reset). Greyed out: no telemetry.</div></section>',
 '<span class="muted">objetivo</span><span class="numeric ': '<span class="muted">target</span><span class="numeric ',
 'Marca algún intento en la lista para analizar sus vueltas.': 'Tick an attempt in the list to analyse its laps.',
 '<section class="panel"><div class="panel-header"><h2>Contra tus amigos</h2><span class="muted" title="el mejor tiempo de cada uno en este evento · resaltado, lo mejor de cada columna">el mejor tiempo de cada uno</span></div>':
   '<section class="panel"><div class="panel-header"><h2>Against your friends</h2><span class="muted" title="everyone\\\'s best time in this event · highlighted: the best in each column">everyone\\\'s best time</span></div>',
 '«Comparar vuelta» pone su mejor vuelta frente a tu mejor vuelta real. ': '«Compare lap» puts their best lap against your real best lap. ',
 'Lo verás en la barra «A contra B», el mapa y la repetición, y en las gráficas. ': 'You will see it in the «A against B» bar, the map and the replay, and in the charts. ',
 'El tiempo cuenta también el récord que importa el juego; «Comparar vuelta» usa la mejor vuelta grabada con el mod, que puede ser más lenta.': 'The time includes the record imported from the game; «Compare lap» uses the best lap recorded with the mod, which may be slower.',
 '">Los botones de comparar llevan a su vuelta o carrera al mapa. Pasa el ratón aquí para más detalle.</div>': '">The compare buttons take their lap or race to the map. Hover here for more detail.</div>', 'Preparando la telemetría…': 'Preparing telemetry…', 'Listo': 'Ready',
}
translated_literals = 0
for spanish, english in sorted(LIT.items(), key=lambda pair: -len(pair[0])):   # longest first, so a short literal never cuts a long one
    quoted = "'" + spanish + "'"
    if quoted in s:
        s = s.replace(quoted, "'" + english + "'"); translated_literals += 1

# 3) Attributes and text of the static markup
HTML = [
 ('<div class="loader-title">Telemetría</div>', '<div class="loader-title">Telemetry</div>'),
 ('<div class="loader-step" id="loaderStep">Leyendo tus carreras…</div>', '<div class="loader-step" id="loaderStep">Reading your races…</div>'),
 ('Telemetría <small>Galactic Racer</small><span class="aurebesh">telemetria</span>', 'Telemetry <small>Galactic Racer</small><span class="aurebesh">telemetry</span>'),
 ('title="Volver al inicio"', 'title="Back to home"'),
 ('title="Lista de eventos de Arcade"', 'title="Arcade event list"'),
 ('title="Importar o exportar tiempos"', 'title="Import or export times"'), ('<span class="top-label">Importar / Exportar</span>', '<span class="top-label">Import / Export</span>'),
 ('<b>Importar tiempos</b>', '<b>Import times</b>'), ('<small>Añade los archivos .swgr de tus amigos</small>', '<small>Add your friends\' .swgr files</small>'),
 ('<b>Exportar mis tiempos</b>', '<b>Export my times</b>'), ('<small>Crea tu archivo de piloto para pasárselo</small>', '<small>Create your pilot file to share it</small>'),
 ('title="Perfil, archivos de piloto y ajustes de la app">', 'title="Profile, pilot files and app settings">'), ('<span class="top-label">Opciones</span>', '<span class="top-label">Options</span>'),
 ('title="Compárate con tus amigos">', 'title="Compare yourself with your friends">'),
 ('title="Modo simple (lo esencial) o tryhard (todo el análisis)"', 'title="Simple mode (the essentials) or tryhard (the whole analysis)"'),
 ('<div class="group"><span>Modo</span>', '<div class="group"><span>Mode</span>'),
 ('<div class="group"><span>Llama del fantasma</span><div class="options" data-preference="ghost_flame_mode"><button type="button" data-value="game">Del juego</button><button type="button" data-value="own">Propia</button><button type="button" data-value="off">No</button>',
  '<div class="group"><span>Ghost flame</span><div class="options" data-preference="ghost_flame_mode"><button type="button" data-value="game">Game</button><button type="button" data-value="own">Own</button><button type="button" data-value="off">Off</button>'),
 ('<div class="group"><span>Tema</span>', '<div class="group"><span>Theme</span>'),
 ('<div class="group"><span>Color del fantasma en pista</span><div class="options" data-preference="ghost_color"><button type="button" data-value="cyan">Cian</button><button type="button" data-value="white">Blanco</button><button type="button" data-value="red">Rojo</button><button type="button" data-value="green">Verde</button><button type="button" data-value="gold">Dorado</button><button type="button" data-value="purple">Morado</button>',
  '<div class="group"><span>In-track ghost colour</span><div class="options" data-preference="ghost_color"><button type="button" data-value="cyan">Cyan</button><button type="button" data-value="white">White</button><button type="button" data-value="red">Red</button><button type="button" data-value="green">Green</button><button type="button" data-value="gold">Gold</button><button type="button" data-value="purple">Purple</button>'),
 ('<div class="group"><span>Fantasma en pista</span><div class="options" data-preference="ghost_enabled"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button>',
  '<div class="group"><span>In-track ghost</span><div class="options" data-preference="ghost_enabled"><button type="button" data-value="on">On</button><button type="button" data-value="off">Off</button>'),
 ('<div class="group"><span>Transparencia del fantasma</span><div class="options" data-preference="ghost_transparency"><button type="button" data-value="low">Baja</button><button type="button" data-value="medium">Media</button><button type="button" data-value="high">Alta</button>',
  '<div class="group"><span>Ghost transparency</span><div class="options" data-preference="ghost_transparency"><button type="button" data-value="low">Low</button><button type="button" data-value="medium">Medium</button><button type="button" data-value="high">High</button>'),
 ('<div class="group"><span>Estela del fantasma</span><div class="options" data-preference="ghost_trail"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button>',
  '<div class="group"><span>Ghost trail</span><div class="options" data-preference="ghost_trail"><button type="button" data-value="on">On</button><button type="button" data-value="off">Off</button>'),
 ('<div class="group"><span>Transparencia de la estela</span><div class="options" data-preference="ghost_trail_transparency"><button type="button" data-value="low">Baja</button><button type="button" data-value="medium">Media</button><button type="button" data-value="high">Alta</button>',
  '<div class="group"><span>Trail transparency</span><div class="options" data-preference="ghost_trail_transparency"><button type="button" data-value="low">Low</button><button type="button" data-value="medium">Medium</button><button type="button" data-value="high">High</button>'),
 ('<div class="group"><span>Efecto holograma</span><div class="options" data-preference="hologram"><button type="button" data-value="off">No</button><button type="button" data-value="soft">Suave</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="strong">Fuerte</button>',
  '<div class="group"><span>Hologram effect</span><div class="options" data-preference="hologram"><button type="button" data-value="off">Off</button><button type="button" data-value="soft">Soft</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="strong">Strong</button>'),
 ('<div class="group"><span>Efecto en la opción elegida</span><div class="options" data-preference="selected_effect"><button type="button" data-value="off">No</button><button type="button" data-value="hologram">Solo si Efecto holograma está activado</button><button type="button" data-value="always">Siempre, aunque esté en No</button></div></div>', '<div class="group"><span>Effect on the chosen option</span><div class="options" data-preference="selected_effect"><button type="button" data-value="off">Off</button><button type="button" data-value="hologram">Only if Hologram effect is on</button><button type="button" data-value="always">Always, even if it is Off</button></div></div>'),
 ('<div class="group"><span>Botones: velocidad de la luz</span><div class="options" data-preference="selected_speed"><button type="button" data-value="slow">Lenta</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="fast">Rápida</button></div></div>', '<div class="group"><span>Buttons: light speed</span><div class="options" data-preference="selected_speed"><button type="button" data-value="slow">Slow</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="fast">Fast</button></div></div>'),
 ('<div class="group"><span>Botones: líneas que bajan</span><div class="options" data-preference="selected_bands"><button type="button" data-value="one">Una</button><button type="button" data-value="two">Dos</button><button type="button" data-value="three">Tres</button></div></div>', '<div class="group"><span>Buttons: descending lines</span><div class="options" data-preference="selected_bands"><button type="button" data-value="one">One</button><button type="button" data-value="two">Two</button><button type="button" data-value="three">Three</button></div></div>'),
 ('<div class="group"><span>Botones: líneas de barrido</span><div class="options" data-preference="selected_lines"><button type="button" data-value="few">Pocas</button><button type="button" data-value="normal">Normales</button><button type="button" data-value="many">Muchas</button></div></div>', '<div class="group"><span>Buttons: scan lines</span><div class="options" data-preference="selected_lines"><button type="button" data-value="few">Few</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="many">Many</button></div></div>'),
 ('<div class="group"><span>Fondo igual que los botones</span><label class="tick-option"><input type="checkbox" id="linkBands"> Usar en el fondo la velocidad y las líneas de los botones</label></div>', '<div class="group"><span>Background same as buttons</span><label class="tick-option"><input type="checkbox" id="linkBands"> Use the speed and the lines of the buttons on the background</label></div>'),
 ('<div class="group"><span>Fondo: velocidad de la luz</span><div class="options" data-preference="page_speed"><button type="button" data-value="slow">Lenta</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="fast">Rápida</button></div></div>', '<div class="group"><span>Background: light speed</span><div class="options" data-preference="page_speed"><button type="button" data-value="slow">Slow</button><button type="button" data-value="normal">Normal</button><button type="button" data-value="fast">Fast</button></div></div>'),
 ('<div class="group"><span>Fondo: líneas que bajan</span><div class="options" data-preference="page_bands"><button type="button" data-value="one">Una</button><button type="button" data-value="two">Dos</button><button type="button" data-value="three">Tres</button></div></div>', '<div class="group"><span>Background: descending lines</span><div class="options" data-preference="page_bands"><button type="button" data-value="one">One</button><button type="button" data-value="two">Two</button><button type="button" data-value="three">Three</button></div></div>'),
 ('<div class="group"><span>Animaciones</span><div class="options" data-preference="animations"><button type="button" data-value="on">Sí</button><button type="button" data-value="off">No</button>',
  '<div class="group"><span>Animations</span><div class="options" data-preference="animations"><button type="button" data-value="on">On</button><button type="button" data-value="off">Off</button>'),
 ('<div class="group"><span>Idioma</span><div class="options" data-preference="language">', '<div class="group"><span>Language</span><div class="options" data-preference="language">'),
 ('El aurebesh necesita la fuente SF Distant Galaxy Symbols (ShyFonts, gratis para uso personal). No va dentro de la app por su licencia: instálala en Windows o ponla en la carpeta «fonts» y vuelve a abrir la app.',
  'Aurebesh needs the SF Distant Galaxy Symbols font (ShyFonts, free for personal use). It is not included in the app because of its licence: install it in Windows or put it in the «fonts» folder and reopen the app.'),
 ('title="Cambiar el idioma de la app">', 'title="Change the app language">'), ('<span id="languageNames"><b>ES</b>&nbsp;·&nbsp;EN&nbsp;·&nbsp;Aurebesh</span>', '<span id="languageNames">ES&nbsp;·&nbsp;<b>EN</b>&nbsp;·&nbsp;Aurebesh</span>'),
 ('title="Se actualiza sola al terminar cada evento"><i></i><span>Leyendo tus archivos</span>', 'title="Updates by itself when each event ends"><i></i><span>Reading your files</span>'),
 ('<div class="page-loading" id="pageLoading" aria-hidden="true">Cargando telemetría…</div>', '<div class="page-loading" id="pageLoading" aria-hidden="true">Loading telemetry…</div>'),
]
for spanish, english in HTML:
    assert s.count(spanish) == 1, ('html', s.count(spanish), spanish[:80])
    s = s.replace(spanish, english)

# Changelog dates in ISO format
s = s.replace("date: '27-10-2026'", "date: '2026-10-27'")
open(ENGLISH_TEMPLATE, 'w', encoding='utf-8').write(s)
# Report of the texts that still look Spanish (a new text that is missing from the lists above)
body = s[s.index('</style>'):]
untranslated = []
SPANISH_WORDS = re.compile(r'[áéíóúñ¿¡]|\b(del|los|las|con|sin|tus?|que|por|para|una|vueltas?|mejor|intentos?|récord|sectores|tiempo|amigos|salida|objetivo|guardar|carpeta|todavía|aquí)\b', re.I)
for line in body.split('\n'):
    if line.strip().startswith('//'):
        continue
    line = re.sub(r'//.*$', '', line)
    for quoted, text in re.findall(r"'((?:[^'\\\n]|\\.)*)'|>([^<>]{2,})<", line):
        candidate = quoted or text
        if SPANISH_WORDS.search(candidate.replace('>Español<', '><')) and candidate not in ('Español',):
            untranslated.append(candidate[:100])
print('literals translated:', translated_literals, '| still in Spanish:', len(set(untranslated)))
for candidate in dict.fromkeys(untranslated):
    print('   ·', candidate)
