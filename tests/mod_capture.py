"""Runs every mod harness on a fresh copy of the mod and snapshots what it prints and writes.

Usage: python3 mod_capture.py <scripts_dir> <output.json>
The clock (os.date / os.time) is made deterministic so two runs of the same code give the same snapshot.
"""
import gzip, json, os, shutil, sys, io, contextlib
from lupa import lua54

SCRIPTS = sys.argv[1]
OUTPUT = sys.argv[2]
TEST = '/tmp/work/test/'
WORK = '/tmp/work/baseline/mod_run/'

STANDARD_SNAPS = ("SNAPS = {{t=20,label='lap 1'},{t=48,label='lap 2 after S1'},{t=66,label='lap 2 closed'},"
                  "{t=75,label='lap 3'},{t=101,label='lap 3 closed'},{t=103.5,label='after finish'},{t=107,label='results'}}")
SCAN2_SNAPS = ("SNAPS = {{t=89.0,label='a'},{t=89.7,label='b'},{t=90.4,label='c'},{t=96.5,label='1'},{t=97.1,label='2'},"
               "{t=97.7,label='3'},{t=104.9,label='fixed'},{t=20,label='lap 1'},{t=48,label='lap 2 after S1'},{t=66,label='lap 2 closed'},"
               "{t=75,label='lap 3'},{t=101,label='lap 3 closed'},{t=103.5,label='after finish'},{t=107,label='results'}}")

# name, harness file, list of runs (each: dict of globals, snaps), mode, files to create before the first run
SCENARIOS = [
    ('basic_pre', 'harness.lua', [{}], 'pre', {}, None),
    ('basic_standing', 'harness.lua', [{}], 'standing', {}, None),
    ('basic_reverse', 'harness.lua', [{}], 'reverse', {}, None),
    ('no_compression', 'harness_nocomp.lua', [{}], 'pre', {}, None),
    ('hud_two_sessions', 'harness_hud.lua', [{}, {}], 'pre', {}, STANDARD_SNAPS),
    ('build_mode', 'harness_build.lua', [{}], 'pre', {}, STANDARD_SNAPS),
    ('keyboard', 'harness_kb.lua', [{}], 'pre', {}, STANDARD_SNAPS),
    ('official_three_sessions', 'harness_off.lua', [{}, {}, {}], 'pre', {}, STANDARD_SNAPS),
    ('point_to_point', 'harness_p2p.lua', [{'RUN': 1}, {'RUN': 2}], None, {}, "SNAPS = {{t=40,label='middle'},{t=125,label='after finish'}}"),
    ('point_to_point_old_hud_ini', 'harness_p2p.lua', [{'RUN': 1}, {'RUN': 2}], None,
     {'OLD:hud.ini': '; viejo\nenabled=true\nx=0.015\ny=0.30\nscale=1.0\nopacity=0.55\n'}, "SNAPS = {{t=40,label='middle'},{t=125,label='after finish'}}"),
    ('safe_mode', 'harness_hud.lua', [{}], 'pre', {'OLD:en_curso.txt': 'panel\n'}, STANDARD_SNAPS),
    # 0.9.22: the panel in English when the app is in English (preferences.txt written by the app)
    ('hud_english', 'harness_hud.lua', [{}, {}], 'pre', {'NEW:preferences.txt': 'language\ten\n'}, STANDARD_SNAPS),
    ('record_scan', 'harness_scan.lua', [{}], 'pre', {}, STANDARD_SNAPS),
    ('record_scan_targets', 'harness_scan2.lua', [{'SPEEDF': 1.0}, {'SPEEDF': 1.12}], 'pre', {}, SCAN2_SNAPS),
]

# Old file names used in the scenarios' pre-files, and their new names (filled in after the renaming)
PREFILE_NAMES = json.loads(os.environ.get('PREFILE_NAMES', '{}'))

DETERMINISTIC_CLOCK = r'''
local realDate = os.date
local fakeNow = 1793120000
os.time = function(t) if t then return 1793120000 end fakeNow = fakeNow + 1; return fakeNow end
os.date = function(fmt, t) fakeNow = fakeNow + 1; return realDate(fmt, t or fakeNow) end
CAPTURED = CAPTURED or {}
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    CAPTURED[#CAPTURED + 1] = table.concat(parts, '\t')
end
'''


def snapshot(directory):
    files = {}
    for root, dirs, names in os.walk(directory):
        dirs[:] = sorted(d for d in dirs if d != 'Scripts')
        for name in sorted(names):
            path = os.path.join(root, name)
            relative = os.path.relpath(path, directory).replace(os.sep, '/')
            data = open(path, 'rb').read()
            if name.endswith('.gz'):
                data = gzip.decompress(data)
            files[relative] = data.decode('utf-8', 'replace')
    return files


def run_scenario(name, harness, runs, mode, prefiles, snaps):
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK + 'Scripts'); os.makedirs(WORK + 'race_ghosts')
    for f in os.listdir(SCRIPTS):
        if f.endswith('.lua'):
            shutil.copy(SCRIPTS + '/' + f, WORK + 'Scripts/' + f)
    for key, content in prefiles.items():
        file_name = PREFILE_NAMES.get(key, key.split(':', 1)[1])
        open(WORK + file_name, 'w').write(content)
    source = open(TEST + harness).read()
    if mode:
        source = source.replace("local MODE = ... or 'pre'", "local MODE = '%s'" % mode)
    printed = []
    if True:
        for run_globals in runs:
            printed.append('===== run')
            runtime = lua54.LuaRuntime()
            g = runtime.globals()
            g.MOD_PATH = WORK + 'Scripts/main.lua'
            for k, v in run_globals.items():
                g[k] = v
            runtime.execute(DETERMINISTIC_CLOCK)
            if snaps:
                runtime.execute(snaps)
            try:
                runtime.execute(source)
            except Exception as error:  # a crash is part of the behaviour to compare
                printed.append('LUA ERROR ' + str(error))
            captured = g.CAPTURED
            printed.extend(captured[i] for i in range(1, len(captured) + 1))
    return {'stdout': '\n'.join(printed), 'files': snapshot(WORK)}


result = {}
for scenario in SCENARIOS:
    result[scenario[0]] = run_scenario(*scenario)
    print(scenario[0], len(result[scenario[0]]['files']), 'files', len(result[scenario[0]]['stdout']), 'chars printed')
json.dump(result, open(OUTPUT, 'w'), indent=1, ensure_ascii=False)
