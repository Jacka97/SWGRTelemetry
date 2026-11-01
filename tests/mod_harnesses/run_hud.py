import glob, os, shutil
from lupa import lua54
shutil.rmtree('/tmp/work/SWGRTelemetry/circuitos', ignore_errors=True)
for f in glob.glob('/tmp/work/SWGRTelemetry/*.txt')+glob.glob('/tmp/work/SWGRTelemetry/*.ini'):
    if not f.endswith('LEEME.txt') and not f.endswith('enabled.txt'): os.remove(f)
for run in [1,2]:
    print('===== sesión', run)
    rt = lua54.LuaRuntime()
    g = rt.globals(); g.MOD_PATH = '/tmp/work/SWGRTelemetry/Scripts/main.lua'
    rt.execute("SNAPS = {{t=20,label='vuelta 1 en curso'},{t=48,label='vuelta 2, tras S1'},{t=66,label='vuelta 2 recién cerrada'},{t=75,label='vuelta 3 en curso'},{t=101,label='vuelta 3 recién cerrada'},{t=103.5,label='tras la meta final'},{t=107,label='resultados (piloto automático)'}}")
    rt.execute(open('/tmp/work/test/harness_hud.lua').read().replace("local MODE = ... or 'pre'", "local MODE = 'pre'"))
print(open('/tmp/work/SWGRTelemetry/metas.txt').read())
