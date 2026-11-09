  // ---------- About and what's new ----------
  // The app and the mod carry the same number since 0.9.10 (both will become 1.0 together)
  const CHANGELOG = [
    { version: '0.9.41', items: [
      'Tramos con la puerta antes del GO, o que parecen circuito y son una sola pasada (Carreras frescas, Arena de la muerte): el tiempo y el mapa ya salen bien',
      'Precisión con carrerilla: los puntos ya no se descuentan dos veces',
      'Precisión: la app marca los puntos que te saltaste en el mapa y en la gráfica de velocidad (tryhard), y la repetición ya no va a saltos',
      'Mapa: zoom con la rueda, arrastrar para moverlo y doble clic para volver a la vista entera',
      'Columnas de la página del evento plegables hacia su lado, y recuadro de Comparar plegable',
      'Portada con una fila por planeta que se desplaza de lado',
      'Holograma renovado: tarjetas, paneles y botones flotando sin caja, con opciones para la luz de los botones y del fondo',
      'Opciones con iconos, y ventana rápida para importar o exportar tiempos',
      'Modo simple: Intentos y Amigos en un solo panel con pestañas',
      'El nombre de los eventos ya no se puede cambiar: es siempre el del juego',
      'Comparar: la barra A contra B ya no se mueve al cambiar entre normal, postcombustión y ramjet',
      'Fantasma en pista: estela desde sus toberas (naranja con la postcombustión, azul con el ramjet) y la llama del motor del juego, que se activan y ajustan en Opciones',
      'Tramos con carrerilla (la vuelta del juego empieza en una puerta después de salir): el tiempo cuenta desde la salida, el S1 va de la salida a la puerta y los demás sectores hasta la meta, así suman el total del juego. Tus mejores tiempos anteriores de esos tramos empiezan de cero',
      'Precisión: vueltas, sectores, panel y diferencia en vivo descuentan el tiempo que restan los puntos, y el resumen dice cuántos puntos pasaste en cada vuelta y sector. Las carreras de Precisión de antes solo cuentan por su total',
      'Arreglados los tirones que iban a más cuanto más rato jugabas: mover el fantasma gastaba memoria en cada fotograma',
      'Quitados los diagnósticos (diagnostics.txt, state_samples.txt, effects.txt y Ctrl+Shift+K)',
    ] },
    { version: '0.9.30', items: [
      'El fantasma se guarda aunque no hayas abierto todavía la app (antes se perdía si faltaba la carpeta race_ghosts)',
      'Los fantasmas guardan la postcombustión y el ramjet (la app completa los de antes con el boost de su carrera), para la estela que vendrá',
      'Carpeta del mod ordenada: config (ajustes), data (récords y mejores tiempos), logs (registro y diagnósticos) y docs (guías). La app y el mod mueven tus archivos solos',
      'Tu archivo de piloto lleva tu fantasma de cada evento tal cual: tus amigos ven tu carrera entera desde la salida, con su altura y giros. Los fantasmas de amigos salen solo de archivos exportados con esta versión (los rehechos con vueltas iban desfasados en la salida)',
      'Panel: en los tramos de una vuelta el tiempo cuenta desde la salida (algunos empiezan el cronómetro de vuelta tras una carrerilla)',
      'Holograma: sus piezas se recolocan en la salida (en salidas en cuesta la moto se quedaba de pie)',
    ] },
    { version: '0.9.29', items: [
      'Fantasma en pista: un holograma de tu vehículo recorre la carrera entera más rápida del evento, la tuya o la de tu amigo más rápido, para comparar trazadas mientras corres. Tu fantasma se guarda al terminar cada evento cuando mejoras tu total',
      'El mod solo graba y muestra el panel en el Arcade. Los reinicios rápidos (antes de 20 s) cuentan como intento pero no guardan archivos',
      'Espacio: la telemetría de los 100 intentos más recientes de cada evento, y siempre la de tus mejores (total, vuelta, salida y cada mejor sector), así la vuelta ideal no cambia al borrar intentos viejos. Los tiempos de todos los intentos se conservan',
      'El archivo para tus amigos lleva la altura y la dirección de tu vehículo, para su fantasma de ti',
      'Color del fantasma en el menú ⚙ (cian, blanco, rojo, verde, dorado o morado); se aplica en la siguiente carrera',
      'Quitados Ctrl+Shift+G y la esfera de prueba de la 0.9.28 (dejaban los controles del juego enganchados)',
    ] },
    { version: '0.9.28', items: [
      'Prueba para el fantasma en pista: Ctrl+Shift+G busca si el juego tiene su propio sistema de fantasmas, y en la primera carrera de cada sesión aparece una esfera delante de ti para comprobar que el juego acepta objetos del mod',
    ] },
    { version: '0.9.27', items: [
      'Panel del juego más completo: velocidad punta y mínima de la vuelta, total previsto a tu ritmo frente al objetivo, y en IDEAL lo que te dejas en la vuelta frente a tus mejores sectores',
      'El objetivo del panel es el más rápido entre tu amigo que te gana, tu récord y el nº1 del juego, con su nombre (la app lo pasa al mod desde los archivos de tus amigos)',
    ] },
    { version: '0.9.26', items: [
      'Ramjet y postcombustión: el mod los graba en cada carrera y en la repetición se ve en todo momento qué usa cada uno (etiqueta junto a A y B, y junto a cada coche en el mapa cuando lo usa). Las carreras grabadas antes no lo tienen',
    ] },
    { version: '0.9.25', items: [
      'Comparador en un solo bloque encima del mapa: primero qué comparas (vuelta lanzada, vuelta 1 de salida, carrera entera o un sector) y luego A y B, que se aplican al momento',
      'La vuelta 1 (salida) va aparte: se compara solo con otras vueltas 1 y tiene su propia vuelta 1 ideal; la vuelta ideal usa solo vueltas lanzadas',
      'Todos los paneles se pueden plegar con el botón de su cabecera, y la app lo recuerda',
      'Tu archivo de piloto lleva también tu mejor vuelta 1 (salida); en Social, tus archivos van arriba del todo',
    ] },
    { version: '0.9.24', items: [
      'La vuelta ideal ya no da saltos entre sectores: cada sector se ajusta a su tiempo oficial, las trazadas se unen suavemente y no se usan vueltas con incidente',
      'Carrera ideal: en «Comparar · Carrera entera» puedes poner en B tu carrera ideal (tu mejor salida en la vuelta 1 y tu vuelta ideal en las demás)',
    ] },
    { version: '0.9.23', items: [
      'Arreglado: con la app abierta, la primera carrera en un circuito nuevo dejaba de cargarse al pasar a su carpeta (solo salía el rival al comparar y la repetición no iba hasta reiniciar la app)',
    ] },
    { version: '0.9.22', items: [
      'Panel del juego: en un circuito nuevo, la diferencia en directo (DIF) de la vuelta 1 aparece ya desde la segunda carrera (antes, desde la tercera)',
      'El panel del juego sale en el idioma de la app (en inglés si la app está en inglés o aurebesh) y las guías vienen también en inglés (README_EN, README_app_EN, TESTING_EN)',
      'Textos más claros: «Comparar vuelta» y «Comparar carrera» dicen dónde verlo en cada modo, «resaltado» en vez de «en verde» (el color cambia con el tema) y Social avisa de los eventos que aún no has corrido con el mod',
    ] },
    { version: '0.9.21', items: [
      'Siempre se compara lo mismo con lo mismo: primero eliges qué comparar (vuelta, carrera entera o un sector) y A y B solo ofrecen cosas de ese tipo; ya no hay vuelta contra carrera ni vuelta repetida en cada vuelta',
      'Barra «A contra B» encima del mapa, siempre a la vista y en los dos modos: quién es A, quién es B, sus tiempos y quién gana',
      'Las gráficas y la tabla siguen a lo que comparas: la carrera entera con sus vueltas marcadas (y la tabla vuelta a vuelta) o solo el sector elegido',
      'Lo que antes se llamaba «ref» ahora es «B» en todas partes',
    ] },
    { version: '0.9.20', items: [
      'Tu archivo de piloto lleva ahora tu mejor carrera entera, vuelta a vuelta, además de tu mejor vuelta: tus amigos pueden comparar la carrera completa contigo («Comparar carrera» y, en el comparador A/B, en «Amigos»)',
      'También lleva los tiempos de los eventos que solo tienen el récord importado del juego, sin telemetría, para que la clasificación con tus amigos tenga todos los eventos',
      'En Social se ve qué trae el archivo de cada amigo: cuántos eventos, cuántos con la carrera entera y cuántos con la vuelta',
    ] },
    { version: '0.9.19', items: [
      'Modo Simple y modo Tryhard (botón de arriba): el simple enseña lo esencial y el mapa primero; el tryhard, todo el análisis',
      'El análisis del evento en dos columnas: el mapa con la repetición se queda a la vista mientras bajas por las vueltas y las gráficas',
      'Barra de arriba más grande, con iconos, y «Telemetría» te devuelve al inicio',
      'Ilustración de cada planeta en las tarjetas e iconos de vehículo junto a cada evento',
      'Vista Tiempos en fichas, varias por fila, para ver más eventos sin bajar',
      'Arreglado: al entrar por primera vez en un circuito, el juego en pantalla completa ya no pasa a ventana (el mod abría un instante una ventana de sistema para crear la carpeta del circuito)'] },
    { version: '0.9.18', items: [
      'Código del mod y de la app en inglés claro, sin abreviaturas, para que sea fácil de leer y revisar',
      'Los archivos de la carpeta del mod pasan a tener nombres en inglés (log.txt, game_records.txt, tracks…): se renombran solos la primera vez, sin perder nada',
      'Los archivos de piloto nuevos usan nombres en inglés por dentro; los de tus amigos de versiones anteriores se siguen leyendo'] },
    { version: '0.9.17', items: [
      'Repetición de la carrera entera con los dos coches a la vez: contra otro intento tuyo o con la referencia repetida en cada vuelta',
      'En el comparador A/B puedes elegir la carrera entera de cualquier intento, aunque no esté marcado'] },
    { version: '0.9.16', items: [
      'Tatooine y los planetas de las carreras de vainas, reconocidos por el código del evento',
      'El tiempo nº1 de cada evento se lee de la clasificación del juego'] },
    { version: '0.9.15', items: [
      'Perfil de piloto: tu nombre y tu color, que viajan en tu archivo de piloto',
      'Pestaña Social: clasificación con todos tus amigos y cara a cara contra el que elijas',
      'En los eventos y en la vista Tiempos salen solo tú y tus 3 mejores amigos',
      'Comparador A/B: elige dos vueltas cualesquiera (tuyas, de amigos o la ideal) y pulsa Comparar',
      'Las vueltas se muestran con el tiempo oficial del juego y «Comparar vuelta» usa tu mejor vuelta real'] },
    { version: '0.9.14', items: [
      'Todos los planetas con su nombre del juego (Crait, Tatooine y los demás), leídos por el mod',
      'Filtro por categoría como en el Arcade del juego: vuelo de prueba, carreras de vainas, precisión, avanzado…',
      'El tiempo nº1 y la categoría de cada evento se guardan aunque no cambie tu récord'] },
    { version: '0.9.13', items: [
      'Repetición nueva: compara un sector, la vuelta o la carrera entera, a tiempo real o con los dos coches en el mismo punto',
      'Zoom que sigue a tu coche, trazadas superpuestas y coches con etiqueta y distancia en metros',
      'Tabla sector a sector bajo el mapa: quién gana cada tramo, y al tocarlo se repite',
      '«Comparar con»: elige la vuelta ideal, la de un amigo o cualquier vuelta tuya desde un desplegable',
      'Inicio en vista «Tiempos»: todos los eventos con tu récord, el nº1, el oro y los tiempos de tus amigos',
      'El mod importa también el tiempo nº1 de cada evento y vuelve a leer los nombres en cada partida'] },
    { version: '0.9.12', items: [
      'Fantasma de salida: la vuelta 1 ya guarda su recorrido aunque salgas desde la parrilla, antes de la línea, así que la diferencia en directo funciona también en la salida',
      'La diferencia en directo de la salida cuenta desde el mismo instante que el cronómetro del panel',
      'Diagnóstico de planetas en registro.txt para recuperar los nombres de planeta de los récords del juego'] },
    { version: '0.9.11', items: [
      'Arreglado el cierre del juego en el menú principal al importar los récords: el mod comprueba que cada texto del juego es de verdad un texto antes de leerlo',
      'Modo seguro más fino: si leer los nombres de evento diera problemas, se desactiva solo eso y los tiempos se siguen importando',
      'El mod guarda sus mensajes en registro.txt, aunque el juego se cierre de golpe'] },
    { version: '0.9.10', items: [
      'La app, en castellano e inglés (menú ⚙ › Idioma), y el aurebesh escrito sobre el inglés',
      'Un solo número de versión para la app y el mod: los dos serán la 1.0 cuando estén terminados',
      'Pantalla «Acerca de y novedades» (menú ⚙), con versiones, créditos y licencias',
      'Aviso de novedades la primera vez que abres una versión nueva',
      'Probada con un año de uso intenso (4.200 intentos): abre en un segundo',
      'El holograma ya no repite la animación de entrada al recargar datos'] },
    { version: 'app 1.9.2 · mod 0.9.9', items: [
      'Pilotos: exporta tus tiempos a un archivo .swgr, añade los de tus amigos y compárate evento a evento, sin internet',
      '«Contra tus amigos» en cada evento, con «Comparar vuelta» en el mapa y las gráficas',
      'Modo seguro del mod: si el juego se cierra de golpe en una parte delicada, esa parte se desactiva y lo demás sigue',
      'Aviso si el mod y la app no son de la misma versión',
      'Holograma en suave, normal o fuerte, con un barrido de luz al encender y sin parpadeos',
      'Filtro «Speeders» que junta coche, moto y rasante',
      'En los tramos de una vuelta ya no se confunde tu récord con la mejor pasada grabada'] },
    { version: 'app 1.9 · mod 0.9.8', items: [
      'Temas Sith, Jedi, Imperial y Galactic Racer, efecto holograma e idioma aurebesh',
      'Pantalla de carga: la app aparece entera cuando están todos los datos',
      'Vehículos por categorías: vainas aparte y los speeders (coche, moto y rasante)',
      'Panel del juego: diferencia en directo frente a tu vuelta de referencia, barras de sector y aviso de récord',
      'La salida se trata aparte: el S1 de la vuelta 1 se compara solo con otras salidas'] },
    { version: 'Antes', items: [
      'Récords del juego importados solos desde el menú de Arcade y nombres de evento legibles',
      'Tramos punto a punto con sectores virtuales',
      'Inicio por planetas, «Dónde pierdes tiempo», vuelta ideal y repetición en el mapa',
      'Telemetría por vuelta y sector, con mapa de velocidad y gráficas de diferencia'] }
  ];
  // Sección «Acerca de» de la página de Opciones: versiones, novedades, créditos y aviso
  // Novedades: la versión actual a la vista; todas las demás, plegadas dentro de «Versiones anteriores»
  function changelogEntry(entry, open) {
    const title = entry.version === 'Antes' ? 'Primeras versiones' : /^\d/.test(entry.version) ? 'Versión ' + escapeHtml(entry.version) + ' <span class="muted">app y mod</span>' : 'Antes: ' + escapeHtml(entry.version);
    return '<details' + (open ? ' open' : '') + '><summary>' + title + '</summary><ul>' +
      entry.items.map(item => '<li>' + escapeHtml(item) + '</li>').join('') + '</ul></details>';
  }
  function changelogHtml() {
    const [current, ...older] = CHANGELOG;
    return (current ? changelogEntry(current, false) : '') +
      (older.length ? '<details class="older-versions"><summary>Versiones anteriores</summary>' + older.map(entry => changelogEntry(entry, false)).join('') + '</details>' : '');
  }
  function aboutSection() {
    const data = state.data;
    const modMatches = data.modVersion && data.expectedModVersion && data.modVersion === data.expectedModVersion;
    let html = '<section class="options-panel" id="optionsAbout">' + optionsHeader('Acerca de', 'Telemetría Galactic Racer · herramienta no oficial para entrenar los contrarrelojes de Arcade');
    html += '<section class="about-versions" style="margin-bottom:18px">' +
      tile('App', 'v' + escapeHtml(data.version || '—'), 'app y mod van con el mismo número') +
      tile('Mod', data.modVersion ? 'v' + escapeHtml(data.modVersion) : '—', data.modVersion
        ? (modMatches ? '<span class="gain">va con esta app</span>' : '<span class="loss">esta app va con la v' + escapeHtml(data.expectedModVersion) + '</span>') : 'no encuentro Scripts\\main.lua') +
      tile('Carreras', String(data.sessions.filter(session => !session.hasBuild).length), 'intentos grabados') +
      tile('Amigos', String(friendPilots().length), friendPilots().length === 1 ? 'archivo de piloto' : 'archivos de piloto') + '</section>';
    html += '<section class="two-columns"><div class="panel"><div class="panel-header"><h2>Novedades</h2></div><div class="changelog">' +
      changelogHtml() + '</div></div>';
    html += '<div class="panel"><div class="panel-header"><h2>Créditos y licencias</h2></div><dl class="credits">' +
      '<dt>Archivo Black y Barlow Semi Condensed</dt><dd>Fuentes del tema Galactic Racer, incluidas en la app con licencia SIL Open Font License 1.1 (ver FONT_LICENSE_OFL.txt).</dd>' +
      '<dt>SF Distant Galaxy (ShyFonts)</dt><dd>Nombres de planeta y aurebesh. No van dentro de la app porque su licencia no lo permite: se usan solo si las tienes instaladas o en la carpeta «fonts».</dd>' +
      '<dt>UE4SS</dt><dd>El cargador de mods en el que funciona el mod de telemetría.</dd>' +
      '<dt>MiniMap y LapRecord de N0M4D</dt><dd>De ahí salen las fuentes de datos del juego que lee el mod.</dd>' +
      '<dt>WebView2 y go-webview2</dt><dd>La ventana de la app usa el motor de Edge que ya trae Windows.</dd>' +
      '</dl><p class="note">Herramienta no oficial hecha por fans, sin relación con Lucasfilm, Disney ni los creadores del juego. Star Wars, STAR WARS: Galactic Racer y los nombres de planetas, vehículos y eventos pertenecen a sus respectivos propietarios.</p></div></section>';
    html += '<section class="panel"><div class="panel-header"><h2>Importante</h2></div><div class="about-warning">' +
      'El mod solo funciona en los eventos de <b>Arcade</b>: en la historia y en el multijugador no graba ni muestra nada. UE4SS sigue cargado con el juego en todos los modos, así que antes de jugar al multijugador se recomienda quitar o renombrar <b>dwmapi.dll</b> en la carpeta Win64 del juego (vuelve a dejarlo como estaba para usar el mod). ' +
      'El mod solo lee datos del juego: no cambia nada de la partida. La app trabaja solo con tus archivos, en tu PC y sin internet.</div>' +
      '<p class="note">Carpeta del mod: <span class="numeric">' + escapeHtml(data.modFolder || '—') + '</span></p></section></section>';
    return html;
  }

