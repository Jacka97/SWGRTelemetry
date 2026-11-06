Código de la página (en español)

Aquí se edita la página. app/web/template.html ya no se toca: lo genera tools/make_web.py uniendo estos archivos, y de él salen index.html e index_en.html (el inglés lo hace tools/english.py).

Para generar: python tools/make_web.py (o la tarea de VS Code «Compilar la app»).

Archivos y orden de montaje
- page.html: el HTML entero, con dos marcadores: "/* @include css */" dentro de <style> y "// @include js" dentro del segundo <script>.
- css/: base, topbar, home, themes, options, loading, event, social, views (en ese orden).
- js/: helpers, names, core, home, event, analysis, compare, charts, options, about, racepanel, pilots, social, start (en ese orden).

Cada archivo es un trozo seguido del original: el orden de las listas CSS_FILES y JS_FILES de tools/make_web.py es el orden final. Todo el JS vive dentro de una misma función (empieza en helpers.js y se cierra en start.js), así que los trozos no son módulos: comparten nombres. Si añades un archivo, añádelo a la lista.

Contenido
- base.css: variables, tema oscuro, fuentes y elementos generales.
- topbar.css: barra de arriba, modo simple, iconos, paneles plegables.
- home.css: portada, resumen del evento, tablas y animaciones.
- themes.css: temas Galactic Racer, Jedi e Imperial y efecto holograma.
- options.css, loading.css, event.css, social.css, views.css: Opciones, pantalla de carga, página del evento, pilotos y Social, vistas de tarjetas/tiempos y Acerca de.
- helpers.js y names.js: utilidades; nombres de eventos y planetas, récords del juego, Aurebesh.
- core.js: estado y navegación.
- home.js y event.js: portada y página del evento.
- analysis.js, compare.js y charts.js: análisis de vuelta y vuelta ideal; comparación A contra B y repetición; gráficas y mapa.
- options.js y about.js: datos, idioma, avisos y Opciones; Acerca de y novedades (CHANGELOG).
- racepanel.js: Opciones, panel en carrera (posición arrastrando, tamaño, colores y filas; guarda timing_panel.ini).
- pilots.js y social.js: archivos de piloto y exportación; perfil y Social.
- start.js: arranque.
