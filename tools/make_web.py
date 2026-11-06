"""Builds the app's two pages: index.html (Spanish, the original) and index_en.html (generated),
with the lap analyzer built in, and checks them."""
import re, subprocess, sys
import os
TOOLS = os.path.dirname(os.path.abspath(__file__)) + '/'
WEB = TOOLS + '../app/web/'

# Montaje de template.html a partir de app/web/src/ (template.html es un archivo generado: no se edita).
# src/page.html es la página entera, con dos marcadores en su lugar:
#   /* @include css */   dentro de <style>       -> se sustituye por los CSS de CSS_FILES, en ese orden
#   // @include js       dentro del 2.º <script> -> se sustituye por los JS de JS_FILES, en ese orden
# Cada archivo es un trozo contiguo del original, así que el orden de las listas es el orden final.
CSS_FILES = [
    'base',      # variables, tema oscuro, fuentes y elementos generales
    'topbar',    # barra de arriba, modo simple, iconos, paneles plegables
    'home',      # portada, resumen del evento, tablas y animaciones
    'themes',    # temas Galactic Racer, Jedi e Imperial, efecto holograma
    'options',   # página de Opciones
    'loading',   # pantalla de carga
    'event',     # página del evento: columnas, mapa, repetición, boost
    'social',    # avisos, pilotos, perfil y Social
    'views',     # vista de tarjetas o de tiempos, Acerca de, intensidad del holograma
]
JS_FILES = [
    'helpers',   # utilidades generales y lectura de tiempos
    'names',     # nombres de eventos y planetas, récords del juego, Aurebesh
    'core',      # modelo (estado) y navegación
    'home',      # portada, iconos, ilustraciones de planetas, vistas
    'event',     # página del evento: pestañas, resumen, intentos
    'analysis',  # análisis de vuelta, vuelta ideal, posiciones en la ruta
    'compare',   # comparación A contra B, repetición y boost
    'charts',    # colores de velocidad, gráficas y mapa
    'options',   # datos, actualización automática, idioma, avisos y Opciones
    'about',     # Acerca de y novedades (CHANGELOG)
    'racepanel', # Opciones: panel en carrera (posición, tamaño, colores y filas)
    'pilots',    # archivos de piloto, clasificaciones y exportación
    'social',    # perfil, secciones de Opciones y Social
    'start',     # arranque de la app
]
def read_bytes(path):
    with open(path, 'rb') as file:
        return file.read()
def join_files(folder, names, extension):
    return b''.join(read_bytes(WEB + 'src/' + folder + '/' + name + '.' + extension) for name in names)
page = read_bytes(WEB + 'src/page.html')
page = page.replace(b'/* @include css */\n', join_files('css', CSS_FILES, 'css'))
page = page.replace(b'// @include js\n', join_files('js', JS_FILES, 'js'))
with open(WEB + 'template.html', 'wb') as file:   # en binario: siempre LF
    file.write(page)
subprocess.run([sys.executable, TOOLS + 'english.py'], check=True)
analyzer = open(TOOLS + 'analysis.js', encoding='utf-8').read()
analyzer = re.sub(r'\n?if \(typeof module[^\n]*\n?', '\n', analyzer)   # the node export is only for the tests
for template, page in (('template.html', 'index.html'), ('template_en.html', 'index_en.html')):
    text = open(WEB + template, encoding='utf-8').read()
    open(WEB + page, 'w', encoding='utf-8').write(text.replace('__ANALYSIS__', analyzer))
# Syntax check of both pages (a badly escaped apostrophe breaks the English page)
syntax = subprocess.run(['node', '-e', '''
const fs = require("fs"); let failed = 0;
for (const page of ["index.html", "index_en.html"]) {
  const html = fs.readFileSync("''' + WEB + '''" + page, "utf8");
  for (const script of html.matchAll(/<script>([\\s\\S]*?)<\\/script>/g)) { try { new Function(script[1]); } catch (error) { console.log(page + ": " + error.message); failed = 1; } }
}
process.exit(failed);'''], capture_output=True, text=True)
if syntax.returncode:
    print('SYNTAX ERROR:', syntax.stdout); sys.exit(1)
# Names left half renamed: undeclared or unused names, fields never written, ids, classes and data attributes
names = subprocess.run(['node', TOOLS + 'check_web.js', WEB + 'template.html', TOOLS + 'analysis.js'] + sorted(__import__('glob').glob(TOOLS + '../app/*.go')), capture_output=True, text=True)
if names.returncode:
    print('NAME CHECK FAILED:\n' + names.stdout); sys.exit(1)
# The English page must keep exactly the same markup: the same classes, ids and data attributes, in the same order
def markup_names(path):
    text = open(path, encoding='utf-8').read()
    return re.findall(r'(?:class|id|data-[a-z-]+)="[^"]*"', text)
spanish_names, english_names = markup_names(WEB + 'template.html'), markup_names(WEB + 'template_en.html')
if spanish_names != english_names:
    import difflib
    print('THE ENGLISH PAGE CHANGED THE MARKUP:'); print('\n'.join(list(difflib.unified_diff(spanish_names, english_names, lineterm='', n=1))[:30])); sys.exit(1)
print('index.html + index_en.html (syntax, names and markup OK)')
