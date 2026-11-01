import glob, os, shutil
from lupa import lua54
shutil.rmtree('/tmp/work/SWGRTelemetry/circuitos', ignore_errors=True)
for f in glob.glob('/tmp/work/SWGRTelemetry/*.txt')+glob.glob('/tmp/work/SWGRTelemetry/*.ini'):
    if not f.endswith('LEEME.txt') and not f.endswith('enabled.txt'): os.remove(f)
for run in [1, 2]:
    print('===== sesión', run)
    rt = lua54.LuaRuntime()
    g = rt.globals(); g.MOD_PATH = '/tmp/work/SWGRTelemetry/Scripts/main.lua'; g.SPEEDF = 1.0 if run == 1 else 1.12
    rt.execute("SNAPS = {{t=89.0,label='aviso a'},{t=89.7,label='aviso b'},{t=90.4,label='aviso c'},{t=96.5,label='aviso 1'},{t=97.1,label='aviso 2'},{t=97.7,label='aviso 3'},{t=104.9,label='aviso fijo'},{t=20,label='vuelta 1 en curso'},{t=48,label='vuelta 2, tras S1'},{t=66,label='vuelta 2 recién cerrada'},{t=75,label='vuelta 3 en curso'},{t=101,label='vuelta 3 recién cerrada'},{t=103.5,label='tras la meta final'},{t=107,label='resultados (piloto automático)'}}")
    rt.execute(open('/tmp/work/test/harness_scan2.lua').read().replace("local MODE = ... or 'pre'", "local MODE = 'pre'"))
print(open('/tmp/work/SWGRTelemetry/metas.txt').read()); print(open('/tmp/work/SWGRTelemetry/fantasmas.txt').read()[:300])
