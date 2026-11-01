"""Clicks through what the screenshot comparison does not cover and checks the files the app writes:
friends (old and new pilot files), profile, settings, language, event name, manual game record and safe mode.
Usage: python3 interaction_test.py <app_binary>"""
import json, os, re, shutil, subprocess, sys, threading
from playwright.sync_api import sync_playwright

BINARY = sys.argv[1]
WORK = '/tmp/work/baseline/interaction_run'
shutil.rmtree(WORK, ignore_errors=True)
shutil.copytree('/tmp/work/baseline/data_old', WORK)
# One event without an imported game record, so the record typed in by hand can be tested
records = os.path.join(WORK, 'records_auto.txt')
open(records, 'w', encoding='utf-8').write(''.join(line for line in open(records, encoding='utf-8') if not line.startswith('LDB_ARC_TT_BIKE_DAL_A_SHORT_01')))
failures = []
def check(condition, message):
    print(('ok    ' if condition else 'FAIL  ') + message)
    if not condition: failures.append(message)
def key_values(name):
    folder = {'preferences.txt': 'config', 'event_names.txt': 'data', 'manual_game_records.txt': 'data', 'safe_mode.txt': 'logs'}.get(name, '')
    path = os.path.join(WORK, folder, name)
    return dict(line.split('\t', 1) for line in open(path, encoding='utf-8').read().splitlines() if '\t' in line) if os.path.exists(path) else {}

process = subprocess.Popen([BINARY, WORK], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
url = None
for _ in range(40):
    match = re.search(r'(http://127\.0\.0\.1:\d+/)', process.stdout.readline())
    if match: url = match.group(1); break
threading.Thread(target=lambda: [None for _ in process.stdout], daemon=True).start()
errors = []
try:
    check(os.path.exists(os.path.join(WORK, 'friends', 'pilot_Rival_ejemplo.swgr')), 'old friend file moved to friends/pilot_<name>.swgr')
    check(not os.path.exists(os.path.join(WORK, 'amigos')) and not os.path.exists(os.path.join(WORK, 'preferencias.txt')), 'old folders and files are gone after the migration')
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={'width': 1440, 'height': 1000}, reduced_motion='reduce')
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.on('console', lambda message: errors.append('console: ' + message.text) if message.type == 'error' else None)
        page.goto(url)
        page.wait_for_function("document.documentElement.classList.contains('booted')")
        def go_to(view):
            page.evaluate("view => { const link = document.createElement('a'); link.dataset.navigate = view; document.body.appendChild(link); link.click(); link.remove(); }", view)
            page.wait_for_timeout(900)
        # Social: the old friend is shown, a new version-2 file is added and then removed
        go_to('social')
        check('Rival (ejemplo)' in page.inner_text('main'), 'friend from an old (version 1) pilot file is listed')
        exported = json.load(open('/tmp/work/baseline/api_after3/exported_pilot.json'))
        exported['pilot'] = 'Nuevo Amigo'; exported['date'] = '2026-10-27 22:00'
        new_file = '/tmp/work/baseline/Nuevo Amigo.swgr'
        json.dump(exported, open(new_file, 'w'))
        page.set_input_files('#pilotFileInput', new_file)
        page.wait_for_timeout(1500)
        check(os.path.exists(os.path.join(WORK, 'friends', 'pilot_Nuevo Amigo.swgr')), 'a version-2 pilot file is added to friends/')
        check('Nuevo Amigo' in page.inner_text('main'), 'the new friend is listed')
        page.click('[data-remove-friend="Nuevo Amigo"]')
        page.wait_for_timeout(1200)
        check(not os.path.exists(os.path.join(WORK, 'friends', 'pilot_Nuevo Amigo.swgr')), 'removing a friend deletes their file')
        page.click('#pilotExport')
        page.wait_for_timeout(2500)
        shared = os.listdir(os.path.join(WORK, 'shared')) if os.path.isdir(os.path.join(WORK, 'shared')) else []
        check(any(name.startswith('pilot_') for name in shared), 'export writes shared/pilot_<name>.swgr')
        # Profile
        go_to('profile')
        page.fill('#profileName', 'Darth Prueba'); page.dispatch_event('#profileName', 'change')
        page.click('[data-color="#3db8ff"]')
        page.wait_for_timeout(800)
        preferences = key_values('preferences.txt')
        check(preferences.get('pilot_name') == 'Darth Prueba' and preferences.get('color') == '#3db8ff', 'profile name and colour saved in preferences.txt')
        check('darth prueba' in page.inner_text('#profileButton').lower(), 'profile button shows the new name')
        # Settings menu
        page.click('#settingsButton')
        page.click('[data-preference="theme"] [data-value="jedi"]')
        page.click('[data-preference="hologram"] [data-value="soft"]')
        page.click('[data-preference="animations"] [data-value="off"]')
        page.wait_for_timeout(800)
        preferences = key_values('preferences.txt')
        check(preferences.get('theme') == 'jedi' and preferences.get('hologram') == 'soft' and preferences.get('animations') == 'off', 'theme, hologram and animations saved')
        classes = page.evaluate("[document.documentElement.dataset.theme, document.documentElement.className]")
        check(classes[0] == 'jedi' and 'hologram-soft' in classes[1] and 'no-animations' in classes[1], 'theme, hologram and animations applied to the page')
        page.click('#themeButton'); page.wait_for_timeout(500)
        check(key_values('preferences.txt').get('theme') == 'imperial', 'theme button moves to the next theme')
        # Event: rename and manual record
        go_to('home')
        page.click('[data-navigate*="DAL"]')
        page.wait_for_function("!document.querySelector('main').classList.contains('pending')")
        page.wait_for_timeout(900)
        page.click('#renameButton')
        page.keyboard.type('Mi circuito'); page.keyboard.press('Enter')
        page.wait_for_timeout(1200)
        names = key_values('event_names.txt')
        check(any(value == 'Mi circuito' for value in names.values()), 'renaming an event writes event_names.txt')
        if page.locator('#gameRecordSave').count():
            page.fill('#gameTotalInput', '1:20.000'); page.fill('#gameLapInput', '19.500'); page.click('#gameRecordSave'); page.wait_for_timeout(1200)
            check(any(value == '80|19.5' for value in key_values('manual_game_records.txt').values()), 'manual game record saved')
        else:
            print('skip  manual game record (every event here has an imported record)')
        # Language: English reloads the page in English
        page.click('#languageButton'); page.wait_for_timeout(2500)
        page.wait_for_function("document.documentElement.classList.contains('booted')")
        check(key_values('preferences.txt').get('language') == 'en' and page.evaluate("document.documentElement.lang") == 'en', 'language button switches to the English page')
        # Safe mode: the notice and "try again"
        open(os.path.join(WORK, 'logs', 'safe_mode.txt'), 'w').write('timing_panel\tblocked\tel juego se cerró\t\n')
        page.reload(); page.wait_for_function("document.documentElement.classList.contains('booted')"); page.wait_for_timeout(800)
        check('timing panel' in page.inner_text('#notices') or 'el panel de tiempos' in page.inner_text('#notices'), 'safe mode notice names the part turned off')
        page.click('#safeModeRetry'); page.wait_for_timeout(1200)
        check(not os.path.exists(os.path.join(WORK, 'logs', 'safe_mode.txt')), '"try again" deletes safe_mode.txt')
        browser.close()
finally:
    process.kill()
check(not errors, 'no page errors' + ('' if not errors else ': ' + ' | '.join(errors[:3])))
print('failures:', len(failures))
sys.exit(1 if failures else 0)
