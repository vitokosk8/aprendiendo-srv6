#!/usr/bin/env python3
"""Segmentos de replicación (RFC 9524) en Linux, que no tiene End.Replicate (módulo 20).

Uso:  python3 replicacion.py NODO      (lee su estado de replicación de estado/NODO.txt)

El estado de replicación de un nodo es, como en el RFC, su lista de RAMAS: a qué nodos
siguientes copia el paquete y con qué Replication-SID. El fichero tiene estas líneas:

  entrada IFAZ GRUPO   (solo en la RAÍZ) el tráfico multicast que entra por IFAZ hacia GRUPO
  sid SID              (en un NODO intermedio) su propio Replication-SID
  rama NOMBRE SID      una por rama: el nodo siguiente y su Replication-SID

Lo que hace cada papel:

  * RAÍZ: recibe el paquete IPv4 multicast de la sede y, por cada rama, lo encapsula en
    IPv6 hacia el Replication-SID de esa rama (un socket IPv6 "en bruto" con protocolo 4:
    el kernel pone la cabecera; con un solo SID es H.Encaps.Red, sin SRH).
  * NODO (End.Replicate): recibe un paquete IPv6 cuyo destino es su Replication-SID y, por
    cada rama, envía una copia con la DIRECCIÓN DE DESTINO REESCRITA hacia el Replication-SID
    de esa rama y el Hop Limit restado en 1. El paquete interior no se toca.

El kernel de un NODO no sabe qué hacer con su Replication-SID: una ruta 'blackhole' lo
descarta en silencio, y este script, que lo ve antes (con un socket AF_PACKET), hace el
trabajo. Las HOJAS no necesitan script: su Replication-SID es un End.DX4 del kernel, que
desencapsula y entrega, que es justo la parte de "hoja" de End.Replicate.
"""
import os, socket, struct, sys, time

NODO = sys.argv[1] if len(sys.argv) > 1 else 'r1'
ESTADO = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'estado', f'{NODO}.txt')
ETH_P_IP, ETH_P_IPV6 = 0x0800, 0x86DD
log = lambda *a: print(time.strftime('%H:%M:%S'), f'[{NODO}]', *a, flush=True)

_estado, _mtime = {'entrada': None, 'sid': None, 'ramas': []}, None
def estado():
    """Relee estado/NODO.txt si ha cambiado."""
    global _estado, _mtime
    try:
        m = os.stat(ESTADO).st_mtime
    except FileNotFoundError:
        return _estado
    if m != _mtime:
        _mtime, e = m, {'entrada': None, 'sid': None, 'ramas': []}
        for l in open(ESTADO):
            l = l.split('#')[0].split()
            if l[:1] == ['entrada'] and len(l) == 3: e['entrada'] = (l[1], l[2])
            elif l[:1] == ['sid'] and len(l) == 2: e['sid'] = l[1]
            elif l[:1] == ['rama'] and len(l) == 3: e['ramas'].append((l[1], l[2]))
        _estado = e
        log('estado de replicación:', ' '.join(f'{n}={s}' for n, s in e['ramas']) or 'sin ramas')
    return _estado

def checksum(cab):
    s = sum(struct.unpack(f'!{len(cab) // 2}H', cab)); s = (s >> 16) + (s & 0xffff); s += s >> 16
    return ~s & 0xffff

def enviar(sock, copia, ramas, origen):
    hechas = []
    for nombre, sid in ramas:
        try:
            sock.sendto(copia(sid), (sid, 0)); hechas.append(nombre)
        except OSError as e:
            log(f'⚠️  rama {nombre} ({sid}): {e}')
    log(f'{origen}: {len(hechas)} {"copia" if len(hechas) == 1 else "copias"} ({" ".join(hechas) or "ninguna rama"})')

def raiz(ifaz, grupo):
    """Papel de RAÍZ: IPv4 multicast de la sede → una copia IPv6 por rama."""
    while not os.path.exists(f'/sys/class/net/{ifaz}'): time.sleep(1)
    rx = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(ETH_P_IP)); rx.bind((ifaz, 0))
    tx = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_IPIP)      # IPv6 + Next Header 4
    g = socket.inet_aton(grupo)
    log(f'raíz: escucho en {ifaz} el grupo {grupo}')
    while True:
        pkt, (_, _, tipo, _, _) = rx.recvfrom(65535)
        if tipo == socket.PACKET_OUTGOING or len(pkt) < 20 or pkt[16:20] != g or pkt[8] <= 1: continue
        ihl = (pkt[0] & 0x0f) * 4
        cab = bytearray(pkt[:ihl]); cab[8] -= 1; cab[10:12] = b'\0\0'; cab[10:12] = struct.pack('!H', checksum(bytes(cab)))
        interior = bytes(cab) + pkt[ihl:]
        enviar(tx, lambda sid: interior, estado()['ramas'], f'{socket.inet_ntoa(pkt[12:16])} → {grupo}')

def nodo():
    """Papel de NODO de replicación: End.Replicate."""
    rx = socket.socket(socket.AF_PACKET, socket.SOCK_DGRAM, socket.htons(ETH_P_IPV6))   # todas las interfaces
    tx = socket.socket(socket.AF_INET6, socket.SOCK_RAW, socket.IPPROTO_RAW)            # cabecera IPv6 escrita por nosotros
    log('nodo: espero paquetes hacia mi Replication-SID')
    while True:
        pkt, (_, _, tipo, _, _) = rx.recvfrom(65535)
        e = estado()
        if tipo == socket.PACKET_OUTGOING or len(pkt) < 40 or not e['sid']: continue
        if pkt[24:40] != socket.inet_pton(socket.AF_INET6, e['sid']): continue
        if pkt[7] <= 1: continue                                    # RFC 9524: Hop Limit ≤ 1 → se descarta
        base = bytearray(pkt); base[7] -= 1                         # resta 1 al Hop Limit
        def copia(sid):
            c = bytearray(base); c[24:40] = socket.inet_pton(socket.AF_INET6, sid)   # DA = Replication-SID de la rama
            return bytes(c)
        enviar(tx, copia, e['ramas'], f'{socket.inet_ntop(socket.AF_INET6, pkt[8:24])} → {e["sid"]}')

if __name__ == '__main__':
    while not os.path.exists(ESTADO): time.sleep(1)
    e = estado()
    raiz(*e['entrada']) if e['entrada'] else nodo()
