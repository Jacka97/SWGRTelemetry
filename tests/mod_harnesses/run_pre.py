import sys, glob, os
from lupa import lua54
for mode in ['pre']:
    for f in glob.glob('/tmp/work/SWGRTelemetry/*.csv')+glob.glob('/tmp/work/SWGRTelemetry/bests.txt'): os.remove(f)
    import shutil; shutil.rmtree('/tmp/work/SWGRTelemetry/circuitos', ignore_errors=True)
    print('=====', mode)
    rt = lua54.LuaRuntime()
    rt.globals().MOD_PATH = '/tmp/work/SWGRTelemetry/Scripts/main.lua'
    rt.execute(open('/tmp/work/test/harness.lua').read().replace("local MODE = ... or 'pre'", f"local MODE = '{mode}'"))
    for f in sorted(glob.glob('/tmp/work/SWGRTelemetry/**', recursive=True)):
        if os.path.isfile(f): print('  file', os.path.basename(f), os.path.getsize(f))
print(open(glob.glob('/tmp/work/SWGRTelemetry/bests.txt')[0]).read())
