#!/usr/bin/env python3
"""Mini-controlador SRv6 del escenario E7.

Lee la topología de la red por BGP-LS (del FRR del contenedor ctl), calcula un camino para
cada servicio según su objetivo, lo convierte en la lista de segmentos más corta posible y lo
programa en el PE de cabecera como una ruta estática con segmentos.

    ./controlador.py              calcula, programa y termina
    ./controlador.py --ver        solo calcula y enseña lo que haría (no toca nada)
    ./controlador.py --bucle      repite cada 5 s y reprograma cuando cambia la topología
    ./controlador.py --limpiar    quita las estáticas de los servicios (vuelven a BGP)

Solo usa la biblioteca estándar de Python. Habla con los routers con "docker exec ... vtysh":
FRR no admite políticas SRv6 por PCEP ni por BGP SR Policy (ver el README del escenario).
"""
import heapq, json, re, subprocess, sys, time

LAB = 'clab-esc-e7'

# ---------------------------------------------------------------------------------------------
# 1. LO QUE PIDEN LOS CLIENTES. Cambia esto y vuelve a ejecutar el script.
#    objetivo: 'retardo' (suma del retardo de los enlaces) o 'igp' (suma de métricas de IS-IS)
#    evitar:   nombre de otro servicio; este no puede usar ningún enlace del camino de aquel
#    El orden importa: un servicio solo puede evitar a otro que esté antes en la lista.
# ---------------------------------------------------------------------------------------------
SERVICIOS = [
    {'nombre': 'ORO ida',      'vrf': 'ORO',   'de': 'r1', 'a': 'r6', 'prefijo': '192.168.20.0/24',  'objetivo': 'retardo'},
    {'nombre': 'ORO vuelta',   'vrf': 'ORO',   'de': 'r6', 'a': 'r1', 'prefijo': '192.168.10.0/24',  'objetivo': 'retardo'},
    {'nombre': 'PLATA ida',    'vrf': 'PLATA', 'de': 'r1', 'a': 'r6', 'prefijo': '192.168.120.0/24', 'objetivo': 'igp', 'evitar': 'ORO ida'},
    {'nombre': 'PLATA vuelta', 'vrf': 'PLATA', 'de': 'r6', 'a': 'r1', 'prefijo': '192.168.110.0/24', 'objetivo': 'igp', 'evitar': 'ORO vuelta'},
]
TABLA = {'ORO': 10, 'PLATA': 11}          # tabla del kernel de cada VRF (para buscar su End.DT4)


def sh(nodo, *cmd):
    """Ejecuta un comando en un contenedor del laboratorio y devuelve su salida."""
    return subprocess.run(['docker', 'exec', f'{LAB}-{nodo}', *cmd], capture_output=True, text=True).stdout

def vtysh(nodo, *lineas):
    args = []
    for l in lineas: args += ['-c', l]
    return sh(nodo, 'vtysh', *args)


# ---------------------------------------------------------------------------------------------
# 2. LEER LA TOPOLOGÍA (BGP-LS). Tres tipos de NLRI nos interesan:
#    node    -> el nombre de cada router (nodeName) a partir de su ID de IS-IS
#    srv6Sid -> los SIDs de nodo (End) de cada router
#    link    -> cada enlace, en un sentido: métrica IGP, retardo, vecino y su End.X
# ---------------------------------------------------------------------------------------------
def leer_topologia():
    rutas = json.loads(vtysh('ctl', 'show bgp link-state link-state json') or '{}').get('routes', {})
    nombres, sids_nodo, enlaces = {}, {}, {}
    nombre = lambda d: nombres.get(d['igpRouterId'], 'r%d' % int(d['igpRouterId'].split('.')[2]))
    for caminos in rutas.values():
        nlri, attr = caminos[0]['nlri'], caminos[0].get('linkStateAttrs', {})
        if nlri['nlriType'] == 'node' and 'nodeName' in attr:
            nombres[nlri['localNodeDescriptors']['igpRouterId']] = attr['nodeName']
    for caminos in rutas.values():
        nlri, attr = caminos[0]['nlri'], caminos[0].get('linkStateAttrs', {})
        if nlri['nlriType'] == 'srv6Sid':
            sids_nodo.setdefault(nombre(nlri['localNodeDescriptors']), []).append(nlri['srv6SidDescriptors']['srv6SidValue'])
        elif nlri['nlriType'] == 'link':
            a, b = nombre(nlri['localNodeDescriptors']), nombre(nlri['remoteNodeDescriptors'])
            enlaces[(a, b)] = {
                'igp': attr.get('igpMetric', 10),
                'retardo': attr.get('delay', 0),
                'vecino': nlri.get('linkDescriptors', {}).get('ipv6NeighborAddress'),
                'local': nlri.get('linkDescriptors', {}).get('ipv6InterfaceAddress'),
                'endx': [x['sid'] for x in attr.get('srv6EndxSids', [])],
            }
    # si un enlace no trae la dirección del vecino, es la dirección local del enlace en sentido contrario
    for (a, b), e in enlaces.items():
        if not e['vecino'] and (b, a) in enlaces: e['vecino'] = enlaces[(b, a)]['local']
    # el SID End de un nodo es el más "corto" de los suyos (en esta red, 5f00:0:N::)
    end = {r: min(s, key=len) for r, s in sids_nodo.items()}
    return enlaces, end


# ---------------------------------------------------------------------------------------------
# 3. CALCULAR. Dijkstra sobre el peso que pida el servicio, sin los enlaces prohibidos.
# ---------------------------------------------------------------------------------------------
def dijkstra(enlaces, origen, peso, prohibidos=()):
    """Distancia mínima desde origen a cada nodo, cuántos caminos mínimos hay y el anterior."""
    dist, cuantos, previo, cola = {origen: 0}, {origen: 1}, {}, [(0, origen)]
    while cola:
        d, u = heapq.heappop(cola)
        if d > dist[u]: continue
        for (a, b), e in enlaces.items():
            if a != u or frozenset((a, b)) in prohibidos: continue
            nd = d + e[peso]
            if nd < dist.get(b, float('inf')):
                dist[b], cuantos[b], previo[b] = nd, cuantos[u], u
                heapq.heappush(cola, (nd, b))
            elif nd == dist[b]:
                cuantos[b] += cuantos[u]            # otro camino igual de bueno (ECMP)
    return dist, cuantos, previo

def camino(enlaces, origen, destino, peso, prohibidos=()):
    _, _, previo = dijkstra(enlaces, origen, peso, prohibidos)
    if destino not in previo: return None
    c = [destino]
    while c[-1] != origen: c.append(previo[c[-1]])
    return c[::-1]


# ---------------------------------------------------------------------------------------------
# 4. CONVERTIR EL CAMINO EN SEGMENTOS. La estática ya fija el primer salto. Desde ahí, se
#    avanza todo lo posible mientras el camino deseado sea EL camino más corto del IGP (único,
#    sin ECMP): basta un End del nodo donde se deja de cumplir. Si ni el siguiente salto lo es,
#    hace falta el End.X de ese enlace. El último segmento es el SID de servicio del PE destino.
# ---------------------------------------------------------------------------------------------
def segmentos(enlaces, end, c, sid_servicio):
    igp = lambda tramo: sum(enlaces[(x, y)]['igp'] for x, y in zip(tramo, tramo[1:]))
    lista, i = [], 1
    while True:
        dist, cuantos, _ = dijkstra(enlaces, c[i], 'igp')
        j = max(k for k in range(i, len(c)) if k == i or (igp(c[i:k + 1]) == dist[c[k]] and cuantos[c[k]] == 1))
        if j == len(c) - 1:
            return lista + [sid_servicio]
        if j > i:
            lista.append(end[c[j]]); i = j            # End: "ve por el camino más corto hasta c[j]"
        else:
            lista.append(enlaces[(c[i], c[i + 1])]['endx'][0]); i += 1   # End.X: "sal por este enlace"


# ---------------------------------------------------------------------------------------------
# 5. PROGRAMAR LOS PE: estática con segmentos en la VRF, sustituyendo la anterior si cambia.
# ---------------------------------------------------------------------------------------------
def sid_servicio(pe, vrf):
    for l in sh(pe, 'ip', '-6', 'route', 'show').splitlines():
        if 'End.DT4' in l and f'vrftable {TABLA[vrf]}' in l: return l.split()[0]

def estaticas_actuales(pe, vrf, prefijo):
    conf, dentro, rutas = vtysh(pe, 'show running-config'), False, []
    for l in conf.splitlines():
        if l.startswith('vrf '): dentro = (l == f'vrf {vrf}')
        elif l.startswith('exit-vrf'): dentro = False
        elif dentro and l.strip().startswith(f'ip route {prefijo} '): rutas.append(l.strip())
    return rutas

def programar(pe, vrf, prefijo, nueva):
    viejas = estaticas_actuales(pe, vrf, prefijo)
    if viejas == ([nueva] if nueva else []): return False
    lineas = ['configure terminal', f'vrf {vrf}'] + [f'no {v}' for v in viejas] + ([nueva] if nueva else []) + ['exit-vrf']
    vtysh(pe, *lineas)
    return True


def ciclo(ver=False, limpiar=False):
    if limpiar:
        for s in SERVICIOS:
            if programar(s['de'], s['vrf'], s['prefijo'], None): print(f"{s['nombre']}: estática quitada")
        return
    enlaces, end = leer_topologia()
    if not enlaces:
        sys.exit('❌ ctl no tiene topología: ¿está establecida la sesión BGP-LS con r2?')
    usados = {}
    for s in SERVICIOS:
        prohibidos = usados.get(s.get('evitar'), set())
        c = camino(enlaces, s['de'], s['a'], s['objetivo'], prohibidos)
        if not c:
            print(f"⚠️  {s['nombre']}: no hay camino que cumpla las restricciones"); continue
        usados[s['nombre']] = {frozenset(p) for p in zip(c, c[1:])}
        sid = sid_servicio(s['a'], s['vrf'])
        segs = segmentos(enlaces, end, c, sid)
        vecino = enlaces[(c[0], c[1])]['vecino']
        if not vecino:
            print(f"⚠️  {s['nombre']}: BGP-LS no trae la dirección de {c[1]} en el enlace {c[0]}-{c[1]}"); continue
        dev = re.search(r'dev (\S+)', sh(s['de'], 'ip', '-6', 'route', 'get', vecino) or '')
        ruta = (f"ip route {s['prefijo']} {vecino} {dev.group(1) if dev else ''} nexthop-vrf default "
                f"segments {'/'.join(segs)}").replace('  ', ' ')
        total = sum(enlaces[p][s['objetivo']] for p in zip(c, c[1:]))
        print(f"{s['nombre']:13} {'-'.join(c):15} {s['objetivo']}={total:<6} segmentos: {' '.join(segs)}")
        if not ver and programar(s['de'], s['vrf'], s['prefijo'], ruta):
            print(f"{'':13} → programado en {s['de']} (VRF {s['vrf']})")


if __name__ == '__main__':
    arg = sys.argv[1] if len(sys.argv) > 1 else ''
    if arg == '--bucle':
        while True:
            print(time.strftime('%H:%M:%S')); ciclo(); time.sleep(5)
    ciclo(ver=(arg == '--ver'), limpiar=(arg == '--limpiar'))
