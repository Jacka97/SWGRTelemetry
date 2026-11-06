"""Saca una versión: python tools/release.py 0.9.32
1) pone el número en el mod y en la app, 2) revisa el mod, 3) genera las páginas, 4) compila el .exe,
5) monta la carpeta del paquete y 6) deja en build/ el zip para amigos y, si tienes las fuentes SF en
fonts_sf/, también el completo."""
import os, re, shutil, subprocess, sys, zipfile
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
def path(*parts): return os.path.join(ROOT, *parts)
def run(command, cwd=ROOT, env=None):
    print('>', ' '.join(command))
    result = subprocess.run(command, cwd=cwd, env=env)
    if result.returncode: sys.exit('FALLO: ' + ' '.join(command))
if len(sys.argv) != 2 or not re.fullmatch(r'\d+\.\d+\.\d+', sys.argv[1]): sys.exit('Uso: python tools/release.py 0.9.32')
version = sys.argv[1]
def replace(file, pattern, new):
    text = open(file, encoding='utf-8').read()
    changed, count = re.subn(pattern, new, text, count=1)
    if not count: sys.exit('No encuentro la versión en ' + file)
    open(file, 'w', encoding='utf-8', newline='').write(changed)
replace(path('mod', 'Scripts', 'main.lua'), r"local VERSION = '[\d.]+'", "local VERSION = '%s'" % version)
replace(path('app', 'main.go'), r'appVersion = "[\d.]+"', 'appVersion = "%s"' % version)
if "version: '%s'" % version not in open(path('app', 'web', 'src', 'js', 'about.js'), encoding='utf-8').read():
    print('AVISO: no hay novedades de la %s en el CHANGELOG de app/web/src/js/about.js' % version)
run(['node', path('tools', 'check_lua.js'), path('mod', 'Scripts', 'main.lua'), path('mod', 'Scripts', 'timing_panel.lua')])
run([sys.executable, path('tools', 'make_web.py')])
build = path('build'); os.makedirs(build, exist_ok=True)
env = dict(os.environ, GOOS='windows', GOARCH='amd64')
run(['go', 'build', '-ldflags', '-H windowsgui', '-o', os.path.join(build, 'GalacticRacerTelemetry.exe'), '.'], cwd=path('app'), env=env)
# The package folder
package = os.path.join(build, 'package', 'SWGRTelemetry')
shutil.rmtree(os.path.join(build, 'package'), ignore_errors=True)
shutil.copytree(path('package'), package)
shutil.copytree(path('mod', 'Scripts'), os.path.join(package, 'Scripts'))
shutil.copy(os.path.join(build, 'GalacticRacerTelemetry.exe'), package)
open(os.path.join(package, 'enabled.txt'), 'w').close()
for folder in ('config', 'data', 'logs', 'race_ghosts', 'friends'):
    os.makedirs(os.path.join(package, folder), exist_ok=True)
    open(os.path.join(package, folder, '.keep'), 'w').close()
for name in os.listdir(os.path.join(package, 'docs')):
    if name.startswith('README'):
        file = os.path.join(package, 'docs', name)
        lines = open(file, encoding='utf-8').read().split('\n')
        lines[0] = re.sub(r'\d+\.\d+\.\d+', version, lines[0])
        open(file, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
def make_zip(name, extra_fonts):
    target = os.path.join(build, name)
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for folder, _, files in os.walk(package):
            relative = os.path.relpath(folder, os.path.dirname(package))
            archive.write(folder, relative)
            for file in files: archive.write(os.path.join(folder, file), os.path.join(relative, file))
        for font in extra_fonts: archive.write(font, os.path.join('SWGRTelemetry', 'fonts', os.path.basename(font)))
    print('Listo:', target)
make_zip('SWGRTelemetry_v%s.zip' % version, [])   # for friends: without the SF fonts (their licence)
own_fonts = [os.path.join(path('fonts_sf'), name) for name in sorted(os.listdir(path('fonts_sf')))] if os.path.isdir(path('fonts_sf')) else []
if own_fonts: make_zip('SWGRTelemetry_completo_v%s.zip' % version, own_fonts)
else: print('(Sin fonts_sf/: no se hace el completo con las fuentes SF)')
