import glob, os, shutil
from lupa import lua54
shutil.rmtree('/tmp/work/SWGRTelemetry/circuitos', ignore_errors=True)
for f in glob.glob('/tmp/work/SWGRTelemetry/*.txt')+glob.glob('/tmp/work/SWGRTelemetry/*.ini'):
    if not f.endswith('LEEME.txt') and not f.endswith('enabled.txt'): os.remove(f)
for run in [1, 2]:
    print('===== sesión', run)
    rt = lua54.LuaRuntime()
    g = rt.globals(); g.MOD_PATH = '/tmp/work/SWGRTelemetry/Scripts/main.lua'; g.RUN = run
    rt.execute("SNAPS = {{t=40,label='a mitad'},{t=125,label='tras la meta'}}")
    rt.execute(open('/tmp/work/test/harness_p2p.lua').read())
print(open('/tmp/work/SWGRTelemetry/metas.txt').read())
print(open('/tmp/work/SWGRTelemetry/bests.txt').read())
