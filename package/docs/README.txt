SWGR Telemetry v0.9.31 - para entrenar OFFLINE
(El mod y la app llevan ahora el mismo número de versión; los dos serán la 1.0 a la vez.)

Instalación
  Copia la carpeta SWGRTelemetry dentro de:
  STAR WARS Galactic Racer\Griffin\Binaries\Win64\ue4ss\Mods\
  Debe quedar ue4ss\Mods\SWGRTelemetry\Scripts\main.lua y ue4ss\Mods\SWGRTelemetry\enabled.txt
  Requiere UE4SS Galactic Racer Edition.

Archivos renombrados en la 0.9.18
  Los archivos de la carpeta del mod tienen ahora nombres en inglés (registro.txt -> log.txt,
  records_auto.txt -> game_records.txt, circuitos -> tracks, amigos -> friends, fuentes -> fonts...).
  No hay que hacer nada: el mod y la app los renombran solos la primera vez, sin perder datos.
  La app se llama ahora GalacticRacerTelemetry.exe: si tenías un acceso directo a la anterior,
  vuelve a crearlo.

Uso
  Entra en un evento de Arcade: el mod detecta el circuito y empieza a grabar solo.
  Ctrl+F9: pausar / reanudar la grabación.
  Ctrl+F10: mostrar / ocultar el panel de tiempos.
  Ctrl+Shift+K: buscar en el juego dónde guarda tus récords (crea record_search.txt;
                record_search_progress.txt dice por dónde va, por si algo falla).
                Funciona también en los menús. Puede congelar el juego unos segundos.

Modo seguro
  Si el juego se cierra de golpe mientras el mod hace algo delicado (crear el panel, leer tus
  récords, la búsqueda de Ctrl+Shift+K o engancharse a la carrera), al volver a abrir el juego
  esa parte queda desactivada y lo demás sigue funcionando. Se apunta en safe_mode.txt y la
  app lo enseña arriba. Si salen errores sin parar (por ejemplo tras un parche del juego), el
  mod deja de grabar en esa partida en vez de insistir.
  Para volver a intentarlo: botón "Volver a intentarlo" de la app, o borra safe_mode.txt.
  Al instalar una versión nueva del mod también se vuelve a intentar todo.
  logs\operation_in_progress.txt: lo crea el mod solo mientras hace una de esas partes; no lo toques.
  logs\log.txt: los mensajes del mod de la última partida, escritos al momento (sirven para
  saber qué pasaba si el juego se cierra de golpe).

Panel de tiempos (solo texto, sin trazadas ni ayudas)
  Sale en el idioma de la app: en castellano, o en inglés si la app está en inglés o aurebesh
  (el cambio se nota al empezar la siguiente carrera).
  Vuelta y tiempo en curso, cada sector con su diferencia con tu mejor sector,
  y abajo tu última vuelta, tu mejor vuelta y la vuelta ideal (suma de mejores sectores).
  TOTAL: tiempo total del evento, que es lo que cuenta en Arcade.
  OBJETIVO: el más rápido entre tu amigo que te gana, tu récord y el nº1 del juego (la fila lleva
  su nombre: PEPE, RÉCORD o Nº1) y, a la derecha, cuánto necesitas por vuelta en las que faltan
  para alcanzarlo (verde si te basta con tu mejor vuelta). Los tiempos de tus amigos los pasa la
  app al mod (rivals.txt) al leer sus archivos de piloto.
  PREVISTO: con qué total acabarías a tu ritmo y la diferencia con el objetivo (no en tramos de
  una vuelta ni en eventos de precisión, donde el juego descuenta tiempo).
  PUNTA: velocidad punta y mínima de la vuelta (verde si igualas las de tu mejor vuelta).
  IDEAL: a la derecha, durante la vuelta, lo que te dejas frente a tus mejores sectores.
  Colores: morado = nuevo mejor sector · verde = mejor que la vuelta anterior ·
           ámbar = peor que la vuelta anterior · gris = tiempo de la vuelta anterior.
  DIF: cuánto vas por delante (verde) o por detrás (rojo) de tu vuelta de referencia en cada
  momento. La referencia es tu vuelta limpia más rápida grabada con esta versión (ghosts.txt);
  la primera vez en un evento aparece desde la segunda vuelta. La vuelta 1 tiene su propia
  referencia (ver Salida): en un circuito nuevo, su DIF sale desde la segunda carrera.
  Salida: en los eventos de varias vueltas se sale con menos velocidad, así que el S1 de la
  vuelta 1 se compara solo con otros S1 de salida, y el tiempo de la vuelta 1 con otras vueltas 1
  (también su DIF). El resto de sectores de la vuelta 1 cuentan como los de cualquier vuelta.
  Barras: una por sector, del color de cómo te fue (morado, verde, ámbar; gris si aún no).
  Al acabar el evento, si mejoras tu récord o bates al nº1, el título lo avisa.
  Al terminar una vuelta se queda 5 segundos con la vuelta completa.
  Al acabar el evento muestra FIN con tu última vuelta y tu total frente al objetivo.
  La primera vez en un circuito aparece al completar la primera vuelta (cuando se
  localiza la meta); después lo recuerda y sale desde el principio.
  config\timing_panel.ini (se crea solo): estilo (style: current, sith o compact), posición (x, y),
  tamaño (scale), opacidad del fondo (opacity), qué filas se ven y si cada sector se compara
  con tu mejor sector o con la vuelta anterior (compare_with: best o previous).

Archivos que genera
  data\event_records.txt            por evento de Arcade: mejor total, mejor vuelta, intentos y objetivo
  data\best_times.txt               tus mejores vueltas y sectores por trazado y vehículo
  data\learned_tracks.txt           meta y número de vueltas de cada circuito
  data\ghosts.txt                   tu vuelta de referencia de cada evento, para la diferencia en directo
  data\game_records.txt             tus récords del juego, leídos del menú de Arcade
  logs\diagnostics.txt              datos internos de la última carrera (para mejorar el mod)
  config\timing_panel.ini           ajustes del panel de tiempos
  race_ghosts\                      tu fantasma de carrera de cada evento y el de tu amigo más rápido
  tracks\<trazado>\                 una carpeta por circuito y sentido, con:
    route.csv                       geometría del circuito y checkpoints (para el visor)
    history.txt                     todas tus vueltas de todas las sesiones
    <fecha>.csv                     una fila cada ~20 ms: tiempo, vuelta, progreso,
                                    posición, velocidad (km/h), rumbo, eventos
    <fecha>_summary.txt             vueltas de la sesión con sectores y diferencias, y el
                                    resultado del evento frente al objetivo

Solo Arcade
  El mod solo graba y muestra el panel en el Arcade: cada evento tiene su vehículo y su build
  predefinidos, así que los tiempos son comparables. Los récords se guardan por evento (su tabla
  de clasificación del juego). En campaña, online y demás modos no hace nada.
  Reinicios rápidos: si reinicias antes de 20 s de carrera, solo se cuenta el intento (no se
  guardan archivos).

Fantasma en pista
  Un holograma de tu vehículo recorre la carrera entera más rápida del evento: la tuya o la de tu
  amigo más rápido (la app la saca de su archivo de piloto). Sirve para comparar trazadas mientras
  corres; no tiene colisión ni cuenta como corredor.
  Tu fantasma se guarda al terminar el evento cuando mejoras tu total (race_ghosts\<evento>.txt).
  La primera vez en un evento no hay fantasma: aparece desde la segunda carrera.
  Color: en la app, menú ⚙ > Color del fantasma en pista (se aplica en la siguiente carrera).
  Si el holograma no se puede crear, sale una esfera en su lugar.

Notas
  - Los tiempos de vuelta son los oficiales del juego. La meta se localiza sola: es el
    checkpoint que se cruza cuando el juego publica la vuelta. Los sectores van de
    checkpoint a checkpoint y suman exactamente el tiempo oficial.
  - Los sectores son los oficiales del juego (su propio cronómetro por sectores) cuando
    coinciden con los checkpoints del circuito; si no, se usan los detectados por el mod.
  - Los checkpoints se detectan por tu avance a lo largo de la ruta (su tiempo coincide
    con el oficial) y, si vas por una trazada alternativa lejos del centro, al cruzar
    su puerta.
  - Si te chocas o retrocedes, la vuelta se marca como "incidente" y el tiempo perdido
    aparece en el sector donde ocurrió.
  - La primera carrera en un circuito nuevo se guarda en la carpeta del mod y la app la pasa
    sola a tracks\<circuito>\ (el mod no abre ninguna ventana, así el juego no sale de la
    pantalla completa); desde entonces el mod ya graba en esa carpeta.
  - El tramo desde la parrilla hasta la primera vez que cruzas la meta no cuenta como vuelta.
  - El panel es una ayuda en carrera: úsalo solo offline.
  - Antes de jugar online o de subir tiempos al ranking: desactiva UE4SS (quita dwmapi.dll).
  - Desinstalar: borra la carpeta SWGRTelemetry, o solo enabled.txt para desactivarlo.
