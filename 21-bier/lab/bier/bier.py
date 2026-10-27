#!/usr/bin/env python3
"""Un router BIER (RFC 8279) en Python, con la cabecera del RFC 8296 sobre IPv6 (módulo 21).

Uso:  python3 bier.py NODO

Ni Linux ni FRR tienen BIER, así que cada router del laboratorio ejecuta este script. Hace lo
mismo que haría un router BIER, en tres partes:

1. CALCULA SU BIFT con las rutas del IGP. Para cada BFER del dominio (dominio.txt), pregunta al
   kernel por qué vecino se llega a su BFR-prefix (la ruta que instaló IS-IS). Los BFER que se
   alcanzan por el mismo vecino comparten entrada, y la F-BM (Forwarding Bit Mask) de esa entrada
   tiene sus bits. Se recalcula cada pocos segundos: si cambia el IGP, cambia la BIFT.

2. REENVÍA (RFC 8279, sección 6.5). Por cada paquete BIER que recibe:
     - si su bit está en el BitString, se queda una copia (entrega local) y lo apaga;
     - mientras queden bits: toma el más bajo, busca su entrada en la BIFT y envía una copia
       al vecino de esa entrada con BitString & F-BM; después apaga esos bits (BitString &= ~F-BM).
   Así nunca sale más de una copia por vecino y ninguna hoja recibe dos.

3. ENCAPSULA, si es el BFIR (entrada.txt): el multicast de la sede se mete en un paquete BIER con
   los bits de los BFER que quieren el grupo.

En el cable, un paquete BIER es: IPv6 (Next Header 253) | cabecera BIER (RFC 8296) | IPv4.
Como en BIERin6, cada salto va a la dirección link-local del vecino con Hop Limit 1. BIERin6
aún no tiene número de Next Header asignado: el laboratorio usa el 253, reservado para
experimentos (RFC 3692).
"""
import json, os, socket, struct, subprocess, sys, time

NODO = sys.argv[1] if len(sys.argv) > 1 else 'r1'
AQUI = os.path.dirname(os.path.abspath(__file__))
PROTO_BIER = 253                          # Next Header "BIER" (en BIERin6, aún sin asignar)
PROTO_IPV4 = 4                            # campo Proto de la cabecera BIER: IPv4 (RFC 8296)
BIFT_ID, BSL = 1, 1                       # BSL 1 = BitString de 64 bits
log = lambda *a: print(time.strftime('%H:%M:%S'), f'[{NODO}]', *a, flush=True)
bits = lambda bs: [k for k in range(1, 65) if bs >> (k - 1) & 1]
fmt = lambda bs: '{' + ','.join(map(str, bits(bs))) + '}'


def dominio():
    """dominio.txt: 'nombre BFR-id BFR-prefix receptor' (receptor '-' si no entrega)."""
    d = {}
    for l in open(os.path.join(AQUI, 'dominio.txt')):
        l = l.split('#')[0].split()
        if len(l) == 4: d[l[0]] = {'id': int(l[1]), 'prefijo': l[2], 'receptor': None if l[3] == '-' else l[3]}
    return d


def calcular_bift(dom):
    """BIFT: {(gateway, interfaz): F-BM}, a partir de las rutas del IGP hacia cada BFR-prefix."""
    bift = {}
    for nombre, b in dom.items():
        if nombre == NODO: continue
        try:
            r = json.loads(subprocess.run(['ip', '-j', '-6', 'route', 'get', b['prefijo']], capture_output=True, text=True).stdout)[0]
        except (IndexError, ValueError):
            continue
        if 'gateway' not in r: continue                         # sin ruta del IGP: ese BFER no está en la BIFT
        clave = (r['gateway'], r['dev'])
        bift[clave] = bift.get(clave, 0) | 1 << (b['id'] - 1)
    return bift


def cabecera(bs, bfir_id, ttl=64):
    """Cabecera BIER no MPLS (RFC 8296), 12 bytes + BitString de 64 bits."""
    w0 = BIFT_ID << 12 | ttl                                    # BIFT-id(20) TC(3) S(1) TTL(8)
    w1 = 0b0101 << 28 | 0 << 24 | BSL << 20 | 0                 # Nibble 0101, Ver 0, BSL, Entropy
    w2 = PROTO_IPV4 << 16 | bfir_id                             # OAM, Rsv, DSCP = 0 · Proto · BFIR-id
    return struct.pack('!III', w0, w1, w2) + struct.pack('!Q', bs)


def checksum(c):
    s = sum(struct.unpack(f'!{len(c) // 2}H', c)); s = (s >> 16) + (s & 0xffff); s += s >> 16
    return ~s & 0xffff


def ttl_menos_uno(ip):
    """Resta 1 al TTL de un paquete IPv4 y rehace su checksum (None si no puede seguir)."""
    if ip[8] <= 1: return None
    ihl = (ip[0] & 0x0f) * 4
    c = bytearray(ip[:ihl]); c[8] -= 1; c[10:12] = b'\0\0'; c[10:12] = struct.pack('!H', checksum(bytes(c)))
    return bytes(c) + ip[ihl:]


class Router:
    def __init__(self):
        self.dom = dominio(); self.yo = self.dom.get(NODO)
        self.bift, self.t = {}, 0
        self.tx = socket.socket(socket.AF_INET6, socket.SOCK_RAW, PROTO_BIER)
        self.tx.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_UNICAST_HOPS, 1)       # un salto, como BIERin6
        self.entrega = socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_RAW)

    def actualizar_bift(self):
        if time.time() - self.t < 4: return
        self.t, nueva = time.time(), calcular_bift(self.dom)
        if nueva != self.bift:
            self.bift = nueva
            lineas = [f'F-BM {fmt(f):12} → vecino {gw} por {dev}' for (gw, dev), f in sorted(nueva.items(), key=lambda x: x[1])]
            open('/tmp/bift.txt', 'w').write('\n'.join(lineas) + '\n')
            log('BIFT:', ' | '.join(lineas) or 'vacía')

    def reenviar(self, bs, bfir_id, ttl, carga, origen):
        self.actualizar_bift()
        hechos = []
        if self.yo and bs >> (self.yo['id'] - 1) & 1:             # mi bit: entrega local
            bs &= ~(1 << (self.yo['id'] - 1))
            ip = ttl_menos_uno(carga)
            if ip and self.yo['receptor']:
                self.entrega.sendto(ip, (self.yo['receptor'], 0)); hechos.append(f'local → {self.yo["receptor"]}')
        while bs:
            k = bits(bs)[0]                                         # el bit más bajo que queda
            entrada = next(((gw, dev, f) for (gw, dev), f in self.bift.items() if f >> (k - 1) & 1), None)
            if not entrada:                                         # nadie sabe llegar: se apaga y sigue
                bs &= ~(1 << (k - 1)); hechos.append(f'sin ruta a {{{k}}}'); continue
            gw, dev, fbm = entrada
            copia = bs & fbm
            self.tx.sendto(cabecera(copia, bfir_id, ttl - 1) + carga, (gw, 0, 0, socket.if_nametoindex(dev)))
            hechos.append(f'{dev} {fmt(copia)}')
            bs &= ~fbm
        n = sum(1 for h in hechos if not h.startswith(('local', 'sin')))
        log(f'{origen}: {n} {"copia" if n == 1 else "copias"} · ' + ' · '.join(hechos))

    def transito(self):
        """Recibe paquetes BIER (Next Header 253): el kernel entrega la carga sin la cabecera IPv6."""
        rx = socket.socket(socket.AF_INET6, socket.SOCK_RAW, PROTO_BIER)
        while True:
            d, (src, *_) = rx.recvfrom(65535)
            if len(d) < 20 or d[4] >> 4 != 0b0101: continue
            ttl = d[3]; bfir_id = struct.unpack('!H', d[10:12])[0]; bs = struct.unpack('!Q', d[12:20])[0]
            if ttl <= 1: continue
            self.reenviar(bs, bfir_id, ttl, d[20:], f'de {src} bits {fmt(bs)}')

    def bfir(self, ifaz, grupos):
        """BFIR: el multicast de la sede entra en el dominio BIER con los bits de sus BFER."""
        while not os.path.exists(f'/sys/class/net/{ifaz}'): time.sleep(1)
        rx = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(0x0800)); rx.bind((ifaz, 0))
        log(f'BFIR: escucho en {ifaz} los grupos {", ".join(grupos)}')
        while True:
            pkt, (_, _, tipo, _, _) = rx.recvfrom(65535)
            if tipo == socket.PACKET_OUTGOING or len(pkt) < 20: continue
            g = socket.inet_ntoa(pkt[16:20])
            if g not in grupos: continue
            dom, receptores = self.dom, leer_entrada()[1].get(g, [])
            bs = 0
            for r in receptores:
                if r in dom: bs |= 1 << (dom[r]['id'] - 1)
            self.reenviar(bs, self.yo['id'], 64, pkt, f'{socket.inet_ntoa(pkt[12:16])} → {g} bits {fmt(bs)}')


def leer_entrada():
    """entrada.txt (solo en el BFIR): 'entrada IFAZ' y 'grupo G BFER BFER…'."""
    p = os.path.join(AQUI, f'entrada-{NODO}.txt')
    if not os.path.exists(p): return None, {}
    ifaz, grupos = None, {}
    for l in open(p):
        l = l.split('#')[0].split()
        if l[:1] == ['entrada'] and len(l) == 2: ifaz = l[1]
        elif l[:1] == ['grupo'] and len(l) >= 2: grupos[l[1]] = l[2:]
    return ifaz, grupos


def recalcular(r):
    """Recalcula la BIFT cada 5 s, haya tráfico o no: así sigue al IGP."""
    while True:
        r.actualizar_bift(); time.sleep(5)


if __name__ == '__main__':
    import threading
    r = Router()
    threading.Thread(target=recalcular, args=(r,), daemon=True).start()
    ifaz, grupos = leer_entrada()
    if ifaz:
        threading.Thread(target=r.transito, daemon=True).start()
        r.bfir(ifaz, list(grupos))
    else:
        log('BFR: espero paquetes BIER')
        r.transito()
