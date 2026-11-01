"""The boost column: a real race with boost added (afterburner, then ramjet); the replay tags in the bar follow it."""
import gzip, os, re, shutil, subprocess, sys, threading
from playwright.sync_api import sync_playwright
BINARY, LANGUAGE = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else 'es')
WORK = '/tmp/work/baseline/boost_run'
shutil.rmtree(WORK, ignore_errors=True); shutil.copytree('/tmp/work/baseline/colega_run', WORK)
open(WORK + '/preferences.txt', 'w').write('language\t%s\npilot_name\tColega\nmode\ttryhard\n' % LANGUAGE)
import glob
path = sorted(glob.glob(WORK + '/telemetry_*.csv.gz') + glob.glob(WORK + '/tracks/*/*.csv.gz'))[0]
lines = gzip.open(path, 'rt').read().split('\n')
out = [lines[0] + ',boost']
for line in lines[1:]:
    if not line: continue
    t = float(line.split(',')[0])
    # In the replay (lap 1 is measured from the line): afterburner for 1-6 s after the start, then ramjet 10-16 s
    code = 'A' if 1 <= t % 25 < 6 else 'R' if 10 <= t % 25 < 16 else 'N'
    out.append(line + ',' + code)
gzip.open(path, 'wt').write('\n'.join(out) + '\n')
for f in os.listdir(WORK): os.utime(os.path.join(WORK, f))
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
        page.click('.event-card >> nth=0'); page.wait_for_timeout(2500)
        page.select_option('#replayScope', 'race'); page.wait_for_timeout(600)
        seen = set()
        duration = page.evaluate("+document.getElementById('replayPosition').max")
        for step in range(0, 1000, 10):
            page.evaluate("(v) => { const r = document.getElementById('replayPosition'); r.value = v; r.dispatchEvent(new Event('input', { bubbles: true })); }", step)
            tag = page.locator('#boostTagA')
            if tag.is_visible(): seen.add(tag.text_content())
        print('      tags seen on A:', sorted(seen))
        names = {'es': ['Normal', 'Postcombustión', 'Ramjet'], 'en': ['Normal', 'Afterburner', 'Ramjet']}[LANGUAGE]
        check(set(names) <= seen, 'the A tag goes through %s' % names)
        check(not page.locator('#boostTagB').is_visible() or page.locator('#boostTagB').text_content() in names, 'B (no boost data or its own) does not break')
        page.screenshot(path='/tmp/work/baseline/audit/boost_%s.png' % LANGUAGE)
        browser.close()
finally:
    process.kill()
check(not errors, 'no page errors %s' % errors[:2]); print('failures:', failures)
