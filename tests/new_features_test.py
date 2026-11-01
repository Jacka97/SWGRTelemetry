"""Checks the 0.9.19 features: home link, Simple/Tryhard modes, sticky map, rival picker, times tiles, vehicle icons, planet art.
Usage: python3 new_features_test.py <app_binary> [language]"""
import re, shutil, subprocess, sys, threading
from playwright.sync_api import sync_playwright
BINARY, LANGUAGE = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else 'es')
WORK = '/tmp/work/baseline/new_features_run'
shutil.rmtree(WORK, ignore_errors=True); shutil.copytree('/tmp/work/baseline/data_old', WORK)
open(WORK + '/preferencias.txt', 'a').write('idioma\t%s\n' % LANGUAGE)
process = subprocess.Popen([BINARY, WORK], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
url = None
for _ in range(40):
    match = re.search(r'(http://127\.0\.0\.1:\d+/)', process.stdout.readline())
    if match: url = match.group(1); break
threading.Thread(target=lambda: [None for _ in process.stdout], daemon=True).start()
failures, errors = 0, []
def check(condition, text):
    global failures
    print(('ok    ' if condition else 'FAIL  ') + text); failures += 0 if condition else 1
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(); page = browser.new_page(viewport={'width': 1440, 'height': 900}, reduced_motion='reduce')
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(url); page.wait_for_function("document.documentElement.classList.contains('booted')"); page.wait_for_timeout(500)
        check(page.locator('.event-card .event-art svg.planet-art').count() >= 2, 'event cards carry a planet illustration')
        check(page.locator('.event-vehicle svg.vehicle-icon').count() >= 2, 'vehicle icons next to the events')
        page.click('[data-home-view="times"]'); page.wait_for_timeout(400)
        check(page.locator('.times-grid .time-tile').count() >= 10, 'times view shows tiles')
        columns = page.evaluate("getComputedStyle(document.querySelector('.times-grid')).gridTemplateColumns.split(' ').length")
        check(columns >= 4, 'several tiles per row (%d)' % columns)
        page.click('.time-tile.clickable'); page.wait_for_function("document.getElementById('compareA') && document.getElementById('compareA').options.length > 0"); page.wait_for_timeout(800)
        check(page.evaluate("!!document.getElementById('analysisLayout')"), 'a tile opens its event')
        layout = page.evaluate("getComputedStyle(document.getElementById('analysisLayout')).gridTemplateColumns.split(' ').length")
        check(layout == 2, 'analysis in two columns')
        page.evaluate("document.getElementById('speedChart').scrollIntoView()"); page.wait_for_timeout(300)
        top = page.evaluate("document.querySelector('.analysis-map').getBoundingClientRect().top")
        check(0 <= top <= 120, 'map stays in view while scrolling (top %d px)' % top)
        page.click('.home-link'); page.wait_for_timeout(800)
        check(page.locator('[data-home-view]').count() == 2, 'the brand takes you home')
        page.click('#modeButton'); page.wait_for_timeout(400)
        check(page.evaluate("document.documentElement.classList.contains('mode-simple')"), 'mode button switches to simple')
        check('mode\tsimple' in open(WORK + '/config/preferences.txt').read(), 'simple mode saved in preferences.txt')
        page.click('[data-home-view="cards"]'); page.wait_for_timeout(300); page.click('.event-card[data-navigate*="DAL"]'); page.wait_for_function("document.getElementById('simpleRival') && document.getElementById('simpleRival').options.length > 0"); page.wait_for_timeout(800)
        check(not page.is_visible('#lapTable') and not page.is_visible('#deltaChart'), 'simple mode hides the lap table and charts')
        check(page.is_visible('#map') and page.is_visible('#simpleRival'), 'simple mode shows the map and the rival picker')
        scopes = page.evaluate("[...document.getElementById('replayScope').options].map(o => o.value)")
        check(not any(scope.startswith('S') for scope in scopes), 'no sector replays in simple mode %s' % scopes)
        options = page.evaluate("[...document.getElementById('simpleRival').options].map(o => o.value)")
        if len(options) > 1:
            page.select_option('#simpleRival', options[1]); page.wait_for_timeout(300)
            check(page.evaluate("document.getElementById('simpleRival').value") == options[1], 'choosing another rival keeps it')
        mapTop = page.evaluate("document.getElementById('analysisLayout').getBoundingClientRect().top + scrollY")
        attemptsTop = page.evaluate("[...document.querySelectorAll('h2')].find(h => /Intentos|Attempts/.test(h.textContent)).getBoundingClientRect().top + scrollY")
        check(mapTop < attemptsTop, 'in simple mode the map comes before the attempts')
        page.click('#modeButton'); page.wait_for_timeout(1200)
        check(page.is_visible('#lapTable'), 'back to tryhard: the lap table is back')
        browser.close()
finally:
    process.kill()
check(not errors, 'no page errors %s' % errors[:2])
print('failures:', failures)
