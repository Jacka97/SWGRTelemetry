"""Checks the 0.9.20 pilot file: the whole best race and the game-record times go in it, and a friend's race can be compared.
Usage: python3 pilot_export_test.py <app_binary> [language]"""
import glob, json, os, re, shutil, subprocess, sys, threading
from playwright.sync_api import sync_playwright
BINARY, LANGUAGE = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else 'es')
WORK = '/tmp/work/baseline/pilot_export_run'
shutil.rmtree(WORK, ignore_errors=True); shutil.copytree('/tmp/work/baseline/data_old', WORK)
open(WORK + '/preferencias.txt', 'a').write('idioma\t%s\n' % LANGUAGE)
failures, errors = 0, []
def check(condition, text):
    global failures
    print(('ok    ' if condition else 'FAIL  ') + text); failures += 0 if condition else 1
def start():
    process = subprocess.Popen([BINARY, WORK], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    url = None
    for _ in range(40):
        match = re.search(r'(http://127\.0\.0\.1:\d+/)', process.stdout.readline())
        if match: url = match.group(1); break
    threading.Thread(target=lambda: [None for _ in process.stdout], daemon=True).start()
    return process, url
process, url = start()
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(); page = browser.new_page(viewport={'width': 1440, 'height': 900}, reduced_motion='reduce')
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(url); page.wait_for_function("document.documentElement.classList.contains('booted')"); page.wait_for_timeout(500)
        # 1) Profile and export
        page.click('#profileButton'); page.wait_for_selector('#profileName')
        page.fill('#profileName', 'Tester'); page.dispatch_event('#profileName', 'change'); page.wait_for_timeout(300)
        page.click('#socialButton'); page.wait_for_selector('#pilotExport')
        check(page.locator('#pilotMessage').inner_text().find('carrera entera' if LANGUAGE == 'es' else 'whole race') >= 0, 'the export note says the whole race goes in')
        os.makedirs(WORK + '/race_ghosts', exist_ok=True)
        open(WORK + '/race_ghosts/LDB_ARC_TT_BIKE_DAL_A_SHORT_01.txt', 'w').write('80.000\t\tevent\n' + ''.join('%.2f\t%d\t%d\t100\t10.0\t0.0\t0.0\n' % (i / 10, i * 100, i * 50) for i in range(30)))
        page.click('#pilotExport'); page.wait_for_function("/Listo|Done/.test(document.getElementById('pilotMessage').textContent)", timeout=60000)
        message = page.locator('#pilotMessage').inner_text(); print('      ' + message)
        path = WORK + '/shared/pilot_Tester.swgr'
        check(os.path.exists(path), 'pilot file written in shared')
        pilot = json.load(open(path, encoding='utf-8'))
        size = os.path.getsize(path)
        events = pilot['events']
        races = {key: value for key, value in events.items() if value.get('bestRaceTelemetry')}
        laps = {key: value for key, value in events.items() if value.get('bestLapTelemetry')}
        timeOnly = {key: value for key, value in events.items() if not value.get('bestLapTelemetry') and not value.get('bestRaceTelemetry')}
        print('      %d events, %d with race, %d with lap, %d time only, %.0f KB' % (len(events), len(races), len(laps), len(timeOnly), size / 1024))
        check(len(races) >= 1, 'at least one event carries its whole race')
        for key, value in races.items():
            race = value['bestRaceTelemetry']
            check(len(race['laps']) == value['plannedLaps'], '%s: %d laps of %d' % (key, len(race['laps']), value['plannedLaps']))
            check(all(abs(lap['trace'][-1][1] - lap['time']) < 0.15 for lap in race['laps']), '%s: each lap time matches its trace' % key)
            officials = [lap.get('officialTime') for lap in race['laps']]
            check(all(officials) and abs(sum(officials) - race['total']) < 0.01, '%s: the official lap times add up to the total (%.3f vs %.3f)' % (key, sum(o or 0 for o in officials), race['total']))
            check(all(len(lap['trace']) >= 10 for lap in race['laps']), '%s: every lap has its trace' % key)
            check(all(len(point) in (5, 6, 8) for lap in race['laps'] for point in lap['trace']), '%s: points are [distance, time, x, y, speed, boost, z, heading]' % key)
        check(len(timeOnly) >= 1 and all(value['total'] > 0 for value in timeOnly.values()), 'events with only a game record go with their time')
        check(all(value.get('timeFrom') in ('game', 'mod') for value in events.values()), 'every event says where its time comes from')
        check(size < 32 << 20, 'file under the 32 MB limit')
        check(any(len(point) == 8 for value in races.values() for lap in value['bestRaceTelemetry']['laps'] for point in lap['trace']), 'race traces carry height and heading')
        starts = {key: value for key, value in events.items() if value.get('bestStartTelemetry')}
        check(len(starts) >= 1 and all(value['bestStartTelemetry']['number'] == 1 and len(value['bestStartTelemetry']['trace']) >= 10 for value in starts.values()), 'the best lap 1 (start) goes with its telemetry (%d events)' % len(starts))
        titles = page.evaluate("[...document.querySelectorAll('#main h2')].map(h => h.firstChild.textContent)")
        check(titles and titles[0] in ('Tu archivo de piloto', 'Your pilot file'), 'Social starts with your pilot file: %s' % titles[:3])
        # 2) The same file as a friend's, a bit slower
        friend = json.loads(json.dumps(pilot)); friend['pilot'] = 'Amigo'; friend['color'] = '#3db8ff'
        for value in friend['events'].values():
            value['total'] = round(value['total'] + 1.5, 3)
            race = value.get('bestRaceTelemetry')
            if race:
                race['total'] = round(race['total'] + 1.5, 3)
                for lap in race['laps']: lap['time'] = round(lap['time'] + 0.5, 3); lap['trace'] = [[p[0], round(p[1] * (1 + 0.5 / lap['time']), 3)] + p[2:] for p in lap['trace']]
        os.makedirs(WORK + '/friends', exist_ok=True)
        json.dump(friend, open(WORK + '/friends/pilot_Amigo.swgr', 'w', encoding='utf-8'))
        page.reload(); page.wait_for_function("document.documentElement.classList.contains('booted')"); page.wait_for_timeout(800)
        page.click('#socialButton'); page.wait_for_selector('#pilotExport'); page.wait_for_timeout(300)
        listing = page.locator('.friend-item', has_text='Amigo').inner_text()
        ghostFiles = glob.glob(WORK + '/race_ghosts/*.friend.txt')
        check('raceGhost' in pilot['events'].get('LDB_ARC_TT_BIKE_DAL_A_SHORT_01', {}), 'your in-game ghost goes in the pilot file')
        friendGhost = open(WORK + '/race_ghosts/LDB_ARC_TT_BIKE_DAL_A_SHORT_01.friend.txt').read().splitlines()
        check(friendGhost[0].split('\t')[1:] == ['Amigo', 'event'] and len(friendGhost) == 31, 'the friend ghost is their in-game ghost: %r' % friendGhost[0])
        check(ghostFiles and all(len(line.split('\t')) == 7 for line in open(ghostFiles[0]).read().splitlines()[1:]), 'friend ghost file has t, x, y, z, heading (%d files)' % len(ghostFiles))
        check(('carrera entera' if LANGUAGE == 'es' else 'whole race') in listing, 'the friend list says what the file holds: ' + listing.replace('\n', ' '))
        social = page.locator('table.social tbody tr').count()
        check(social >= len(events), 'Social standings cover every event of the friend (%d rows, %d events)' % (social, len(events)))
        # 3) Compare the race from the friends panel
        raceEvent = next(iter(races))
        page.click('.home-link'); page.wait_for_timeout(400)
        page.click('[data-home-view="cards"]'); page.wait_for_timeout(300)
        page.click('.event-card[data-navigate="%s"]' % raceEvent)
        page.wait_for_function("document.getElementById('compareA') && document.getElementById('compareA').options.length > 0"); page.wait_for_timeout(800)
        check(page.locator('[data-compare-friend-race="Amigo"]').count() == 1, 'friends panel offers «Comparar carrera»')
        page.click('[data-compare-friend-race="Amigo"]'); page.wait_for_timeout(1200)
        check(page.evaluate("document.getElementById('replayScope').value") == 'race', 'comparing the race replays the whole race')
        values = lambda picker: page.evaluate("[...document.getElementById('%s').options].map(o => o.value).filter(Boolean)" % picker)
        selectedB = page.locator('#selectedB').inner_text()
        check(selectedB.startswith('Amigo') and ('su mejor carrera' if LANGUAGE == 'es' else 'their best race') in selectedB, 'the bar says B is the friend\'s best race: ' + selectedB)
        check(page.locator('#versusGap').inner_text().strip() != '', 'the bar says who wins: ' + page.locator('#versusGap').inner_text())
        # Like with like: comparing races, A and B only list whole races
        optionsA, optionsB = values('compareA'), values('compareB')
        check(all(value.startswith('race:') for value in optionsA), 'race: A lists only your whole races %s' % optionsA[:4])
        check(all(value.startswith(('race:', 'friendrace:', 'idealrace')) for value in optionsB) and 'idealrace' in optionsB and any(value.startswith('friendrace:') for value in optionsB), 'race: B lists only whole races, the friend\'s too %s' % optionsB[:4])
        rows = page.evaluate("[...document.querySelectorAll('#sectorComparison tbody tr td:first-child')].map(td => td.textContent)")
        check(rows[0].startswith('V') and len(rows) == len(races[raceEvent]['bestRaceTelemetry']['laps']) + 1, 'race: the table goes lap by lap %s' % rows)
        check(('carrera' if LANGUAGE == 'es' else 'race') in page.locator('#chartsTitle').inner_text().lower(), 'race: the charts are of the race: ' + page.locator('#chartsTitle').inner_text())
        # Laps: only laps
        page.select_option('#replayScope', 'lap'); page.wait_for_timeout(600)
        optionsA, optionsB = values('compareA'), values('compareB')
        check(not any(value.startswith('race:') or value.startswith('friendrace:') for value in optionsA + optionsB), 'lap: A and B list only laps')
        check('Amigo' in page.locator('#selectedB').inner_text() and ('su mejor vuelta' if LANGUAGE == 'es' else 'their best lap') in page.locator('#selectedB').inner_text(), 'lap: the friend\'s race becomes his best lap: ' + page.locator('#selectedB').inner_text())
        # A sector: the table and charts follow it
        page.select_option('#replayScope', 'S2'); page.wait_for_timeout(600)
        check('S2' in page.locator('#chartsTitle').inner_text(), 'sector: the charts are of S2: ' + page.locator('#chartsTitle').inner_text())
        check(not any(value.startswith('race:') for value in values('compareB')), 'sector: B lists laps')
        # The bar stays in view while scrolling down to the charts
        page.evaluate("document.getElementById('speedChart').scrollIntoView()"); page.wait_for_timeout(300)
        top = page.evaluate("document.getElementById('versusBar').getBoundingClientRect().top")
        check(0 <= top <= 900, 'the A-against-B bar stays in view (top %d px)' % top)
        # Back to race with the A/B pickers: two races
        page.select_option('#replayScope', 'race'); page.wait_for_timeout(600)
        check(page.evaluate("document.getElementById('compareB').value").startswith(('race:', 'friendrace:')), 'switching to race puts a race in B')
        page.click('[data-compare-friend="Amigo"]'); page.wait_for_timeout(800)
        check(page.evaluate("document.getElementById('replayScope').value") == 'lap' and ('su mejor vuelta' if LANGUAGE == 'es' else 'their best lap') in page.locator('#selectedB').inner_text(), '«Comparar vuelta» compares laps: ' + page.locator('#selectedB').inner_text())
        # 4) Simple mode: the rivals follow what is compared
        page.click('#modeButton'); page.wait_for_timeout(1000)
        options = values('simpleRival')
        check(not any(value.startswith('friendrace:') for value in options), 'simple, lap: only laps as rivals %s' % options)
        page.select_option('#replayScope', 'race'); page.wait_for_timeout(800)
        options = values('simpleRival')
        check(options and all(value.startswith(('friendrace:', 'lap:', 'idealrace')) for value in options) and 'idealrace' in options and any(value.startswith('friendrace:') for value in options), 'simple, race: whole races as rivals %s' % options)
        check(page.locator('#simpleRival').is_visible() and page.locator('#versusBar #simpleRival').count() == 1, 'simple: the rival picker is inside the A-against-B bar')
        check(('su mejor carrera' if LANGUAGE == 'es' else 'their best race') in page.locator('#selectedB').inner_text(), 'simple, race: B is the friend\'s race: ' + page.locator('#selectedB').inner_text())
        page.select_option('#replayScope', 'lap'); page.wait_for_timeout(600)
        check(('su mejor vuelta' if LANGUAGE == 'es' else 'their best lap') in page.locator('#selectedB').inner_text() or 'ideal' in page.locator('#selectedB').inner_text().lower(), 'simple, back to lap: a lap in B: ' + page.locator('#selectedB').inner_text())
        page.click('#modeButton'); page.wait_for_timeout(600)
        page.screenshot(path='/tmp/work/baseline/pilot_export_%s.png' % LANGUAGE, full_page=False)
        browser.close()
finally:
    process.kill()
check(not errors, 'no page errors %s' % errors[:2])
print('failures:', failures)
