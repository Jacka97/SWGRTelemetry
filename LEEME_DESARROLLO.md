# SWGR Telemetry — código fuente (0.9.31)

Ábrelo en VS Code con *Archivo > Abrir carpeta…* sobre esta carpeta. VS Code te propondrá las extensiones recomendadas (Go, Lua, Python).

## Qué hay
| Carpeta | Contenido |
|---|---|
| `mod/Scripts/` | El mod de UE4SS: `main.lua` (grabación, récords, fantasma, diagnósticos) y `timing_panel.lua` (panel en carrera). Se copia tal cual a `...\ue4ss\Mods\SWGRTelemetry\Scripts\`. |
| `app/` | La app en Go: servidor local + ventana WebView2. `server.go` (API y datos), `sessions.go` (lee los resúmenes), `maintenance.go` (limpieza, compresión, boost de fantasmas), `pilot_files.go` (archivos de piloto y fantasmas de amigos), `mod_folder.go` (carpetas y migraciones). |
| `app/web/src/` | La página en español, repartida en `page.html` (HTML), `css/*.css` y `js/*.js`. **Es el original que se edita** (ver `app/web/src/LEEME.md`). `make_web.py` los une en `template.html` y de ahí salen `index.html` e `index_en.html`; los tres se generan. |
| `tools/` | `make_web.py` genera las páginas (y el inglés con `english.py`) y las revisa; `analysis.js` analiza la telemetría (va dentro de la página); `check_lua.js` y `check_web.js` buscan nombres mal escritos. |
| `tests/` | Las pruebas que uso (Python + Playwright). Tienen rutas de Linux; sirven de referencia. `mod_harnesses/` simula el juego para probar el mod. |

## Compilar
Necesitas Go 1.24+, Python 3 y Node.js. En VS Code: *Terminal > Ejecutar tarea*:
1. **Instalar dependencias de las herramientas** (solo la primera vez).
2. **Compilar la app**: genera las páginas y deja el `.exe` en `build/`.
3. **Revisar el mod (Lua)** antes de copiar `main.lua` al juego.

## Sacar una versión
1. Escribe las novedades en `CHANGELOG` de `app/web/src/js/about.js` (y su inglés en `tools/english.py`, o saldrán en español en la página inglesa).
2. *Terminal > Ejecutar tarea > Sacar versión* y escribe el número (por ejemplo `0.9.32`).
3. En `build/` quedan `SWGRTelemetry_v0.9.32.zip` (para amigos) y, si pones tus fuentes SF en `fonts_sf/`, `SWGRTelemetry_completo_v0.9.32.zip`.

La tarea pone el número en el mod y en la app, revisa el mod, genera las páginas, compila y monta el paquete con `package/` (LEEME, guías y `fonts/Readme.txt`) más las carpetas vacías.

## Ojo
- El mod solo para jugar OFFLINE; quita UE4SS (`dwmapi.dll`) antes de jugar online.
- No metas imágenes ni recursos del juego en el código (EULA y derechos).
